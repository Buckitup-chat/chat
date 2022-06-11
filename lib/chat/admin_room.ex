defmodule Chat.AdminRoom do
  @moduledoc "Admin Room functions"

  alias Chat.AdminDb
  alias Chat.Card
  alias Chat.Identity

  def is_created? do
    AdminDb.db()
    |> CubDB.has_key?(:pub_key)
  end

  def create do
    if is_created?() do
      raise "Admin room already created"
    end

    "Admin room"
    |> Identity.create()
    |> tap(&AdminDb.put(:pub_key, Identity.pub_key(&1)))
  end

  def pub_key do
    AdminDb.get(:pub_key)
  end

  def visit(%Identity{} = admin) do
    %{hash: hash} = admin_card = admin |> Card.from_identity()

    AdminDb.put({:new_admin, hash}, admin_card)
  end

  # todo: deprecate
  def enlist(%Card{hash: hash} = new_admin) do
    AdminDb.put({:new_admin, hash}, new_admin)
  end

  def admin_list do
    AdminDb.values({:new_admin, 0}, {:"new_admin\0", 0})
  end
end
