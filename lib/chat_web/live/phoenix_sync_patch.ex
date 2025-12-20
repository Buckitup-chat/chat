defmodule ChatWeb.PhoenixSyncPatch do
  @moduledoc """
  Patched version of Phoenix.Sync.LiveView.sync_stream/4 that fixes the nil resume bug.

  This is a temporary workaround until Phoenix.Sync fixes the issue upstream.
  The bug is in phoenix_sync 0.6.1 line 421 where it passes `resume: nil` to Electric.Client.stream/2.

  Usage:

      import ChatWeb.PhoenixSyncPatch

      def mount(_params, _session, socket) do
        {:ok, sync_stream_fixed(socket, :users, User)}
      end
  """

  alias Electric.Client.Message

  @doc """
  Fixed version of Phoenix.Sync.LiveView.sync_stream/4 that handles nil resume messages.
  """
  def sync_stream_fixed(socket, name, query, opts \\ []) do
    {electric_opts, stream_opts} = Keyword.split(opts, [:client])

    component =
      case socket.assigns do
        %{myself: %Phoenix.LiveComponent.CID{} = component} -> component
        _ -> nil
      end

    if Phoenix.LiveView.connected?(socket) do
      client = Keyword.get_lazy(electric_opts, :client, &Phoenix.Sync.client!/0)

      Phoenix.LiveView.stream(
        socket,
        name,
        client_live_stream_fixed(client, name, query, component),
        stream_opts
      )
    else
      Phoenix.LiveView.stream(socket, name, [], stream_opts)
    end
  end

  @doc """
  Handle sync events - same as Phoenix.Sync.LiveView.sync_stream_update/3
  """
  def sync_stream_update(socket, event, opts \\ []) do
    Phoenix.Sync.LiveView.sync_stream_update(socket, event, opts)
  end

  # Private functions - patched versions

  defp client_live_stream_fixed(client, name, query, component) do
    pid = self()

    client
    |> Electric.Client.stream(query, live: false, replica: :full, errors: :stream)
    |> Stream.transform(
      fn -> {[], nil} end,
      &live_stream_message/2,
      &update_mode_fixed(&1, {client, name, query, pid, component})
    )
  end

  defp live_stream_message(
         %Message.ChangeMessage{headers: %{operation: :insert}, value: value},
         acc
       ) do
    {[value], acc}
  end

  defp live_stream_message(%Message.ChangeMessage{} = msg, {updates, resume}) do
    {[], {[msg | updates], resume}}
  end

  defp live_stream_message(%Message.ControlMessage{}, acc) do
    {[], acc}
  end

  defp live_stream_message(%Message.ResumeMessage{} = resume, {updates, nil}) do
    {[], {updates, resume}}
  end

  defp live_stream_message(%Electric.Client.Error{} = error, _acc) do
    {[], {error, nil}}
  end

  defp update_mode_fixed({%Electric.Client.Error{} = error, _resume}, _state) do
    raise error
  end

  # THIS IS THE FIX: Only pass resume option if resume is not nil
  defp update_mode_fixed({updates, resume}, {client, name, query, pid, component}) do
    # Send all updates
    for event <- updates |> Enum.reverse() |> Enum.map(&wrap_msg(&1, name, component)),
        do: send(pid, {:sync, event})

    send(pid, {:sync, wrap_event(component, {name, :loaded})})

    # Start live streaming task
    Task.start_link(fn ->
      # FIX: Build stream options conditionally based on resume
      stream_opts =
        if resume do
          [resume: resume, replica: :full]
        else
          [replica: :full]
        end

      client
      |> Electric.Client.stream(query, stream_opts)
      |> Stream.each(&send_live_event(&1, pid, name, component))
      |> Stream.run()
    end)
  end

  defp send_live_event(%Message.ChangeMessage{} = msg, pid, name, component) do
    send(pid, {:sync, wrap_msg(msg, name, component)})
  end

  defp send_live_event(%Message.ControlMessage{control: :up_to_date}, pid, name, component) do
    send(pid, {:sync, wrap_event(component, {name, :live})})
  end

  defp send_live_event(_msg, _pid, _name, _component) do
    nil
  end

  # Helper functions from Phoenix.Sync.LiveView
  require Record
  Record.defrecordp(:event, :"$electric_event", [:name, :operation, :item, opts: []])
  Record.defrecordp(:component_event, :"$electric_component_event", [:component, :event])

  defp wrap_msg(%Message.ChangeMessage{headers: %{operation: operation}} = msg, name, component)
       when operation in [:insert, :update] do
    wrap_event(component, event(operation: :insert, name: name, item: msg.value))
  end

  defp wrap_msg(%Message.ChangeMessage{headers: %{operation: :delete}} = msg, name, component) do
    wrap_event(component, event(operation: :delete, name: name, item: msg.value))
  end

  defp wrap_event(nil, event) do
    event
  end

  defp wrap_event(component, event) do
    component_event(component: component, event: event)
  end
end
