defmodule Chat.AdminRoom do
  @moduledoc "Admin Room functions"

  alias Chat.Admin.MediaSettings
  alias Chat.AdminDb
  alias Chat.Card
  alias Chat.Identity

  def created? do
    AdminDb.db()
    |> CubDB.has_key?(:pub_key)
  end

  def create do
    if created?() do
      raise "Admin room already created"
    end

    AdminDb.put(:media_settings, %MediaSettings{})

    "Admin room"
    |> Identity.create()
    |> tap(&AdminDb.put(:pub_key, Identity.pub_key(&1)))
  end

  def pub_key do
    AdminDb.get(:pub_key)
  end

  def visit(%Identity{public_key: admin_pub_key} = admin) do
    admin_card = admin |> Card.from_identity()

    AdminDb.put({:new_admin, admin_pub_key}, admin_card)
  end

  def admin_list do
    AdminDb.values({:new_admin, 0}, {:"new_admin\0", 0})
    |> Enum.to_list()
  end

  def store_wifi_password(
        password,
        %Identity{private_key: private, public_key: public} = _admin_room_identity
      ) do
    secret = Enigma.compute_secret(private, public)

    AdminDb.put(:wifi_password, Enigma.cipher(password, secret))
  end

  def get_wifi_password(
        %Identity{private_key: private, public_key: public} = _admin_room_identity
      ) do
    secret = Enigma.compute_secret(private, public)

    :wifi_password
    |> AdminDb.get()
    |> Enigma.decipher(secret)
  rescue
    _ -> nil
  end

  def get_media_settings do
    media_settings = AdminDb.get(:media_settings)

    if media_settings do
      media_settings
    else
      %MediaSettings{}
    end
  end

  def store_media_settings(%MediaSettings{} = media_settings),
    do: AdminDb.put(:media_settings, media_settings)
end
