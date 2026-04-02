defmodule ChatWeb.ElectricStatusController do
  use ChatWeb, :controller

  alias ChatWeb.Plugs.ElectricReadiness

  def show(conn, _params) do
    {status_code, body} =
      case ElectricReadiness.check_readiness() do
        :ready ->
          {200, %{status: "ready", message: "System ready"}}

        {:not_ready, phase, message} ->
          {503, %{status: phase, message: message}}
      end

    conn
    |> put_status(status_code)
    |> json(body)
  end
end
