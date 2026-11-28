defmodule ChatWeb.MainLive.Page.LogoutRouter do
  @moduledoc """
  Route logout & backup events of `ChatWeb.MainLive.Index` (`logout-*` / `logout:*`) to
  `Page.Logout`.

  Siblings: `LoginRouter`, `LobbyRouter`, `SyncRoomRouter`.
  """

  alias ChatWeb.MainLive.Page

  #
  # LiveView events
  #

  def event(socket, event) do
    case event do
      {"logout-open", _} ->
        socket |> Page.Logout.open()

      {"logout-go-middle", _} ->
        socket |> Page.Logout.go_middle()

      {"logout-go-share", _} ->
        socket |> Page.Logout.go_share()

      {"logout:toggle-password-visibility", _} ->
        socket |> Page.Logout.toggle_password_visibility()

      {"logout:toggle-password-confirmation-visibility", _} ->
        socket |> Page.Logout.toggle_password_confirmation_visibility()

      {"logout-download-insecure", _} ->
        socket
        |> Page.Logout.generate_backup("")
        |> Page.Logout.go_final()

      {"logout-download-with-password", %{"logout" => form}} ->
        socket |> Page.Logout.download_on_good_password(form)

      {"logout-check-password", %{"logout" => form}} ->
        socket |> Page.Logout.check_password(form)

      {"logout-wipe", _} ->
        socket
        |> Page.Shared.untrack_onliners_presence()
        |> Page.Login.clear()
        |> Page.Logout.wipe()

      {"logout-close", _} ->
        socket |> Page.Logout.close()
    end
  end

  #
  # Process messages
  #

  def info(socket, {:key_shared, _params}), do: socket |> Page.Logout.go_final()
end
