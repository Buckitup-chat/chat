defmodule ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.LiveStream do
  @moduledoc """
  Live shape streams for dialog messages, reactions and receipts, forwarded
  to the subscriber process as tagged messages.
  """

  import ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.Ingest, only: [gated_client: 2]

  alias Electric.Client.Message
  alias Electric.Client.ShapeDefinition

  def start_message_stream(dialog_hash, base_url, subscriber_pid, auth) do
    client = gated_client(base_url, auth)

    shape =
      ShapeDefinition.new!("dialog_messages",
        where: "dialog_hash = '#{dialog_hash}'"
      )

    spawn(fn ->
      client
      |> Electric.Client.stream(shape, live: false, replica: :full, errors: :stream)
      |> Stream.transform(
        fn -> {[], nil} end,
        fn
          %Message.ChangeMessage{headers: %{operation: op}, value: value}, {msgs, resume}
          when op in [:insert, :update] ->
            {[], {[value | msgs], resume}}

          %Message.ResumeMessage{} = resume, {msgs, nil} ->
            {[], {msgs, resume}}

          _other, acc ->
            {[], acc}
        end,
        fn {msgs, resume} ->
          send(subscriber_pid, {:dialog_msgs_loaded, Enum.reverse(msgs)})
          run_live_stream(client, shape, resume, &forward_dialog_msg(&1, subscriber_pid))
        end
      )
      |> Stream.run()
    end)
  end

  def start_reaction_stream(dialog_hash, base_url, subscriber_pid, auth) do
    start_auxiliary_stream(
      "dialog_message_reactions",
      dialog_hash,
      base_url,
      subscriber_pid,
      :reactions_loaded,
      :reaction_change,
      auth
    )
  end

  def start_receipt_stream(dialog_hash, base_url, subscriber_pid, auth) do
    start_auxiliary_stream(
      "dialog_message_receipts",
      dialog_hash,
      base_url,
      subscriber_pid,
      :receipts_loaded,
      :receipt_change,
      auth
    )
  end

  defp start_auxiliary_stream(
         table,
         dialog_hash,
         base_url,
         subscriber_pid,
         loaded_tag,
         change_tag,
         auth
       ) do
    client = gated_client(base_url, auth)

    shape =
      ShapeDefinition.new!(table,
        where: "dialog_hash = '#{dialog_hash}'"
      )

    spawn(fn ->
      client
      |> Electric.Client.stream(shape, live: false, replica: :full, errors: :stream)
      |> Stream.transform(
        fn -> {[], nil} end,
        fn
          %Message.ChangeMessage{headers: %{operation: op}, value: value}, {rows, resume}
          when op in [:insert, :update] ->
            {[], {[value | rows], resume}}

          %Message.ResumeMessage{} = resume, {rows, nil} ->
            {[], {rows, resume}}

          _other, acc ->
            {[], acc}
        end,
        fn {rows, resume} ->
          send(subscriber_pid, {loaded_tag, Enum.reverse(rows)})
          run_live_stream(client, shape, resume, &forward_change(&1, subscriber_pid, change_tag))
        end
      )
      |> Stream.run()
    end)
  end

  defp run_live_stream(client, shape, resume, handler) do
    opts =
      if resume,
        do: [resume: resume, replica: :full, errors: :stream],
        else: [replica: :full, errors: :stream]

    client
    |> Electric.Client.stream(shape, opts)
    |> Stream.each(handler)
    |> Stream.run()
  end

  defp forward_dialog_msg(%Message.ChangeMessage{headers: %{operation: :insert}, value: v}, pid),
    do: send(pid, {:dialog_msg_new, v})

  defp forward_dialog_msg(%Message.ChangeMessage{headers: %{operation: :update}, value: v}, pid),
    do: send(pid, {:dialog_msg_updated, v})

  defp forward_dialog_msg(%Message.ControlMessage{control: :up_to_date}, pid),
    do: send(pid, {:dialog_msg_live})

  defp forward_dialog_msg(_message, _pid), do: :ok

  defp forward_change(%Message.ChangeMessage{headers: %{operation: op}, value: v}, pid, tag)
       when op in [:insert, :update],
       do: send(pid, {tag, v})

  defp forward_change(_message, _pid, _tag), do: :ok
end
