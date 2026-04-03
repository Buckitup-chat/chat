defmodule ChatWeb.Plugs.ElectricReadiness do
  @moduledoc """
  Returns 503 Service Unavailable when the Electric stack is not yet ready.

  Checks in order:
  1. Chat.Db.repo_ready?/0 — PostgreSQL repo is alive and queryable
  2. Electric.StatusMonitor reports :active — all Electric children ready
     (pg lock acquired, replication client, connection pool, shape log collector)

  On failure returns JSON with `status` and `message` fields so clients can
  display or act on the current phase.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case check_readiness() do
      :ready ->
        conn

      {:not_ready, phase, message} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{status: phase, message: message}))
        |> halt()
    end
  end

  @doc """
  Returns `:ready` or `{:not_ready, phase, message}`.

  Phases (in order): `"db_initializing"`, `"electric_starting"`.

  Electric status transitions: `:waiting` → `:starting` → `:active`.
  """
  def check_readiness do
    cond do
      not Chat.Db.repo_ready?() ->
        {:not_ready, "db_initializing", "Database initializing"}

      not electric_stack_running?() ->
        {:not_ready, "electric_starting", "Electric stack starting"}

      true ->
        :ready
    end
  end

  defp electric_stack_running? do
    Electric.StatusMonitor.status("electric-embedded") == :active
  end
end
