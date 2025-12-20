defmodule ChatWeb.PlainController do
  @moduledoc "Serve plain pages"
  alias Chat.AdminRoom
  use ChatWeb, :controller

  def privacy_policy(conn, _) do
    text = AdminRoom.get_privacy_policy_text()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, text)
  end

  def electric_test(conn, _) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, "priv/static/electric_test.html")
  end
end
