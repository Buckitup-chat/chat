defmodule Chat.Pq.OwnerBootstrap do
  @moduledoc "Registers the first user_card as the device owner (pq_admin) in AdminDB."

  alias Chat.AdminDb
  alias Chat.NetworkSynchronization.Electric.SyncBotCardPusher

  def maybe_register_owner(user_hash, sign_pkey) do
    with nil <- owner(),
         :ok <- AdminDb.put_new(:pq_admin, %{user_hash: user_hash, sign_pkey: sign_pkey}) do
      :registered
    else
      _ -> :already_registered
    end
  end

  @doc "Registers the owner from a stored user_card; a device's SyncBot card never owns a device."
  def maybe_register_card(%{user_hash: user_hash, sign_pkey: sign_pkey} = card) do
    if SyncBotCardPusher.sync_bot_card?(card),
      do: :not_eligible,
      else: maybe_register_owner(user_hash, sign_pkey)
  end

  def owner do
    AdminDb.get(:pq_admin)
  end

  def owner?(user_hash) do
    case owner() do
      %{user_hash: ^user_hash} -> true
      _ -> false
    end
  end
end
