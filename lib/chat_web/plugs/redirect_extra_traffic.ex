defmodule ChatWeb.Plugs.RedirectExtraTraffic do
  def init(opts), do: opts

  def call(conn, _) do
    case conn.host do
      "buckitup.app" -> conn
      "localhost" -> conn
      "offline-chat.gigalixirapp.com" -> conn
      _other -> block(conn)
    end
  end

  defp block(conn) do
    conn
    |> Plug.Conn.halt()
  end

  # defp redirect(conn) do
  #   home_url = ChatWeb.Router.Helpers.main_index_url(conn, :index)

  #   conn
  #   |> Phoenix.Controller.redirect(external: home_url)
  #   |> Plug.Conn.halt()
  # end
end