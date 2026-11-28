defmodule ChatWeb.MainLive.Page.RecoverKeyShare.Shares do
  @moduledoc """
  State of the uploaded key shares on the recover key share page: removing a share,
  picking the reference hash sign, marking invalid, duplicate and broken shares,
  their chip colours and order, and the changeset/recovery error.

  Part of the `ChatWeb.MainLive.Page.RecoverKeyShare` namespace.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Chat.KeyShare

  def check_broken_content(socket, shares),
    do:
      if(Enum.any?(shares, &KeyShare.broken?/1),
        do: socket |> assign(:recovery_error, "Unable to read file content"),
        else: socket
      )

  def remove(socket, ref),
    do: socket |> assign(:shares, Enum.filter(socket.assigns.shares, &(&1.ref != ref)))

  def set_hash_sign(%{assigns: %{shares: shares, hash_sign: _hash_sign}} = socket) do
    case Enum.empty?(shares) do
      true ->
        socket |> assign(:hash_sign, nil)

      _ ->
        socket
        |> assign(
          :hash_sign,
          shares |> Enum.min_by(&(&1.ref |> String.to_integer())) |> Map.get(:hash_sign)
        )
    end
  end

  def validate_hash(%{assigns: %{shares: shares, hash_sign: hash_sign}} = socket) do
    socket
    |> assign(
      :shares,
      shares
      |> Enum.map(fn share ->
        Map.put(
          share,
          :valid,
          if(KeyShare.broken?(share), do: true, else: share.hash_sign == hash_sign)
        )
      end)
    )
  end

  def check(%{assigns: %{shares: _shares} = params} = socket) do
    socket |> assign(:changeset, params |> KeyShare.check())
  end

  def mark_duplicates(%{assigns: %{shares: shares}} = socket) do
    duplicates_list = shares |> KeyShare.look_for_duplicates()
    exclude_list = duplicates_list |> Enum.map(& &1.exclude)
    index_list = duplicates_list |> Enum.map(& &1.ref) |> List.flatten()

    shares =
      shares
      |> Enum.map(fn share ->
        case share.ref in index_list && share.ref not in exclude_list && share.valid do
          true -> Map.put(share, :duplicate, true)
          false -> Map.put(share, :duplicate, false)
        end
      end)

    socket |> assign(:shares, shares)
  end

  def set_bg(%{assigns: %{shares: shares}} = socket) do
    socket
    |> assign(
      :shares,
      shares
      |> Enum.map(fn share ->
        case {share.valid, share.duplicate, Map.has_key?(share, :broken)} do
          {true, false, false} -> Map.put(share, :bg, "bg-gray-50")
          {true, true, false} -> Map.put(share, :bg, "bg-yellow-50")
          _ -> Map.put(share, :bg, "bg-red-50")
        end
      end)
    )
  end

  def sort(%{assigns: %{shares: shares}} = socket) do
    valid_shares = shares |> Enum.filter(&(&1.valid && !Map.has_key?(&1, :broken)))
    invalid_shares = shares |> Enum.reject(&(&1.valid && !Map.has_key?(&1, :broken)))

    socket
    |> assign(
      :shares,
      valid_shares
      |> Enum.sort_by(&{&1.key, &1.duplicate})
      |> Enum.concat(invalid_shares)
    )
  end

  def clean_recovery_error(socket), do: socket |> assign(:recovery_error, nil)
end
