defmodule ChatWeb.Plugs.PreferSSL do
  @moduledoc """
  Redirects traffic to https if it is enabled
  """

  def init(opts), do: opts

  if Application.compile_env(:chat, ChatWeb.Endpoint)[:https] do
    def call(%{scheme: :https} = conn, _), do: conn
    def call(conn, _), do: redirect(conn)

    defp redirect(conn) do
      ["https://", conn.host, conn.request_path, may_be_query_string(conn)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join()
      |> then(&Phoenix.Controller.redirect(conn, external: &1))
      |> Plug.Conn.halt()
    end

    defp may_be_query_string(conn) do
      if conn.query_string != "" do
        "?#{conn.query_string}"
      end
    end
  else
    def call(conn, _), do: conn
  end
end
