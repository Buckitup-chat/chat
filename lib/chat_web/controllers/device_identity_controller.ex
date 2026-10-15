defmodule ChatWeb.DeviceIdentityController do
  @moduledoc "Returns the device identity: device_id, sync_bot and admin user hashes and public keys."

  use ChatWeb, :controller

  alias Chat.DeviceId
  alias Chat.Pq.OwnerBootstrap
  alias Chat.Pq.ServerIdentity

  def show(conn, _params) do
    json(conn, %{
      device_id: DeviceId.id(),
      sync_bot: sync_bot_identity(),
      admin: admin_identity()
    })
  end

  defp sync_bot_identity do
    %{sign_pkey: sign_pkey} = ServerIdentity.get()

    %{
      user_hash: ServerIdentity.user_hash(),
      sign_pkey: Base.encode64(sign_pkey, padding: false)
    }
  catch
    :exit, _ -> nil
  end

  defp admin_identity do
    case OwnerBootstrap.owner() do
      %{user_hash: user_hash, sign_pkey: sign_pkey} ->
        %{
          user_hash: user_hash,
          sign_pkey: Base.encode64(sign_pkey, padding: false)
        }

      _ ->
        nil
    end
  end
end
