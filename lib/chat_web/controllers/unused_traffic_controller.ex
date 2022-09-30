defmodule ChatWeb.UnusedTrafficController do
  @moduledoc "Silent redirected traffic"
  use ChatWeb, :controller

  def not_available(conn, _) do
    conn
    |> resp(:service_unavailable, "Try later")
    |> put_resp_header("retry-after", "600")
    |> send_resp()
  end
end
