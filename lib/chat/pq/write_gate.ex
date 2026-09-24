defmodule Chat.Pq.WriteGate do
  @moduledoc """
  Checks vouch chain access for write (ingest) mutations when gate_mode is not :open.

  Use `and_gate/3` to wrap a shape's check callback with gate enforcement:

      check: WriteGate.and_gate(&Validation.allowed(&1, pop_ctx), :user_card)
      check: WriteGate.and_gate(&Validation.allowed(&1, pop_ctx), :dialog_messages, owner: "sender_hash")
  """

  alias Chat.AdminDb
  alias Chat.Data.VouchToken
  alias Chat.DeviceId
  alias Chat.Pq.OwnerBootstrap

  def and_gate(check_fn, shape_name, opts \\ []) do
    field = Keyword.get(opts, :owner, "user_hash")

    fn operation ->
      with :ok <- check_fn.(operation) do
        check_access(op_user_hash(operation, field), shape_name)
      end
    end
  end

  def check_access(user_hash, shape_name) do
    case gate_mode() do
      :open -> :ok
      _mode -> enforce(user_hash, shape_name)
    end
  end

  defp gate_mode, do: AdminDb.get(:pq_gate_mode) || :open

  defp enforce(nil, _shape_name), do: :ok

  defp enforce(user_hash, shape_name) do
    case OwnerBootstrap.owner() do
      nil ->
        :ok

      %{user_hash: ^user_hash} ->
        :ok

      %{user_hash: owner_hash} ->
        check_chain(owner_hash, user_hash, shape_name)
    end
  end

  defp check_chain(owner_hash, user_hash, shape_name) do
    scope = write_scope(DeviceId.id(), shape_name)

    case VouchToken.chain_distance(owner_hash, user_hash, scope) do
      {:ok, _} -> :ok
      _ -> {:error, "not_in_trust_chain"}
    end
  end

  defp op_user_hash(%{operation: :insert, changes: changes}, field), do: changes[field]
  defp op_user_hash(%{data: data}, field), do: data[field]

  defp write_scope(device_id, shape_name) do
    "device.#{device_id}.storage.write.#{to_string(shape_name)}"
  end
end
