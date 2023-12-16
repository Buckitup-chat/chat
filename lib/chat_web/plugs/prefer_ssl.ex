defmodule ChatWeb.Plugs.PreferSSL do
  @moduledoc """
  Redirects traffic to https if it is enabled
  """

  def init(opts), do: opts

  if Application.compile_env(:chat, ChatWeb.Endpoint)[:https] do
    def call(conn, _) do
      conn
      |> Phoenix.Controller.redirect(external: ~p"https://#{conn.host}")
      |> Plug.Conn.halt()
    end
  else
    def call(conn, _), do: conn
  end
end
