defmodule Chat.AdminRoom do
  @moduledoc "Admin Room functions"

  alias Chat.Admin.{BackupSettings, CargoSettings, MediaSettings}
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

    AdminDb.put(:backup_settings, %BackupSettings{})
    AdminDb.put(:cargo_settings, %CargoSettings{})
    AdminDb.put(:media_settings, %MediaSettings{})

    "Admin room"
    |> Identity.create()
    |> tap(fn room_identity ->
      AdminDb.put(:pub_key, Identity.pub_key(room_identity))
    end)
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

  def get_backup_settings do
    backup_settings = AdminDb.get(:backup_settings)

    if backup_settings do
      backup_settings
    else
      %BackupSettings{}
    end
  end

  def store_backup_settings(%BackupSettings{} = backup_settings),
    do: AdminDb.put(:backup_settings, backup_settings)

  def get_cargo_user, do: AdminDb.get(:cargo_user)

  def store_cargo_user(user_identity), do: AdminDb.put(:cargo_user, user_identity)

  def get_cargo_settings do
    cargo_settings = AdminDb.get(:cargo_settings)

    if cargo_settings do
      %CargoSettings{}
      |> Map.merge(cargo_settings)
    else
      %CargoSettings{}
    end
  end

  def parse_weight_setting(weight_sensor) do
    with true <- weight_sensor !== %{},
         type <- weight_sensor[:type],
         true <- is_binary(type) and byte_size(type) > 0,
         name <- weight_sensor[:name],
         true <- is_binary(name) and byte_size(name) > 0,
         opts <- Map.drop(weight_sensor, [:name, :type]) |> Map.to_list() |> fix_parity() do
      {:ok, {name, type, opts}}
    else
      :error
    end
  end

  defp fix_parity(opts) do
    if is_binary(opts[:parity]) do
      opts
      |> Keyword.delete(:parity)
      |> Keyword.put(:parity, opts[:parity] |> String.to_existing_atom())
    else
      opts
    end
  end

  def store_cargo_settings(%CargoSettings{} = cargo_settings),
    do: AdminDb.put(:cargo_settings, cargo_settings)

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
