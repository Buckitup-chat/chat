defmodule ChatWeb.Plugs.RedirectExtraTraffic do
  def init(opts), do: opts

  def call(conn, _) do
    if conn.port in [443, 80, 4000] do
      case conn.host do
        "buckitup.app" -> conn
        "localhost" -> conn
        "offline-chat.gigalixir.com" -> conn
        _other -> redirect(conn)
      end
    else
      block(conn)
    end
  end

  defp block(conn) do
    conn
    |> Plug.Conn.halt()
  end

  defp redirect(conn) do
    home_url = ChatWeb.Router.Helpers.main_index_url(conn, :index)

    conn
    |> Phoenix.Controller.redirect(external: home_url)
    |> Plug.Conn.halt()
  end
end
