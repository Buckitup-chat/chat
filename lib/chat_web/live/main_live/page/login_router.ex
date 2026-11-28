defmodule ChatWeb.MainLive.Page.LoginRouter do
  @moduledoc """
  Route login and key ring events of `ChatWeb.MainLive.Index`: user creation, auth restore,
  key ring import/export and key share recovery. Owns `on_login/1`, the lobby setup that
  runs once a user is loaded.

  Siblings: `LogoutRouter`, `LobbyRouter`, `SyncRoomRouter`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias ChatWeb.MainLive.Page
  alias ChatWeb.Router.Helpers, as: Routes

  #
  # LiveView events
  #

  def event(socket, event) do
    case event do
      {"login", %{"login" => %{"name" => name}}} ->
        socket
        |> Page.Login.create_user(name)
        |> on_login()

      {"restoreAuth", data} when data == %{} ->
        socket |> Page.Login.handshaked()

      {"restoreAuth", data} ->
        socket |> restore_auth(data)

      {"export-keys", %{"export_key_ring" => %{"code" => code}}} ->
        socket |> Page.ExportKeyRing.send_key_ring(code |> String.to_integer())

      {"login:" <> action, params} ->
        socket |> route_login_action({action, params})
    end
  end

  defp restore_auth(%{assigns: %{live_action: :export}} = socket, data),
    do: socket |> Page.Login.load_user(data)

  defp restore_auth(socket, data) do
    socket
    |> Page.Login.handshaked()
    |> Page.Login.load_user(data)
    |> on_login()
  end

  defp route_login_action(socket, action) do
    case action do
      {"request-key-ring", _} ->
        socket
        |> Page.Login.close()
        |> Page.ImportKeyRing.init()

      {"import-own-key-ring", _} ->
        socket
        |> Page.Login.close()
        |> Page.ImportOwnKeyRing.init()

      {"recover-key-share", _} ->
        socket
        |> Page.Login.close()
        |> assign(:mode, :recover_key_share)

      {"my-keys-file-submit", _} ->
        socket

      {"import-own-keyring-decrypt",
       %{"import_own_keyring_password" => %{"password" => password}}} ->
        socket |> Page.ImportOwnKeyRing.try_password(password)

      {"import-own-keyring-reupload", _} ->
        socket |> Page.ImportOwnKeyRing.back_to_file()

      {"import-own-keyring:drop-password-error", _} ->
        socket |> Page.ImportOwnKeyRing.drop_error()

      {"import-keyring-close", _} ->
        socket
        |> Page.ImportKeyRing.close()
        |> assign(:need_login, true)

      {"import-own-keyring-close", _} ->
        socket
        |> Page.ImportOwnKeyRing.close()
        |> assign(:need_login, true)

      {"recovery-key-close", _} ->
        socket |> assign(:need_login, true)

      {"export-code-close", _} ->
        socket |> push_event("chat:redirect", %{url: Routes.main_index_path(socket, :index)})
    end
  end

  #
  # Process messages
  #

  def info(socket, message) do
    case message do
      {:exported_key_ring, keys} ->
        socket
        |> Page.ImportKeyRing.save_key_ring(keys)
        |> Page.Login.store()
        |> Page.ImportKeyRing.close()
        |> on_login()

      {:key_recovered, [me, rooms]} ->
        socket
        |> assign(:step, nil)
        |> assign(:mode, :lobby)
        |> Page.Login.load_user(me, rooms)
        |> Page.Login.store()
        |> on_login()

      {:sync_stored_room, key, room_count} ->
        socket
        |> Page.Login.sync_stored_room(key, room_count)
        |> Page.Lobby.show_new_room(%{})

      :reset_rooms_to_backup ->
        socket |> Page.Login.reset_rooms_to_backup()
    end
  end

  @doc "Set up the lobby, dialogs, logout and presence for a freshly loaded user"
  def on_login(socket) do
    socket
    |> Page.Lobby.init()
    |> Page.Dialog.init()
    |> Page.Logout.init()
    |> Page.Shared.track_onliners_presence()
    |> Page.LiveRouter.action()
  end
end
