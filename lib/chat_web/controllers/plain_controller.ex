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
end
