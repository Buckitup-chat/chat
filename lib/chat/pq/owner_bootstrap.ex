defmodule Chat.Pq.OwnerBootstrap do
  @moduledoc "Registers the first user_card as the device owner (pq_admin) in AdminDB."

  alias Chat.AdminDb

  def maybe_register_owner(user_hash, sign_pkey) do
    with nil <- owner(),
         :ok <- AdminDb.put_new(:pq_admin, %{user_hash: user_hash, sign_pkey: sign_pkey}) do
      :registered
    else
      _ -> :already_registered
    end
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
