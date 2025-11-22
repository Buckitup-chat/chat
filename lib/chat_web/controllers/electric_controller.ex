defmodule ChatWeb.ElectricController do
  use ChatWeb, :controller

  alias Phoenix.Sync.Writer
  alias Writer.Format

  alias Chat.Data.Schemas.User

  def ingest(conn, %{"mutations" => mutations}) when is_list(mutations) do
    # TanStack DB-style ingestion, users-only, via Phoenix.Sync.Writer
    {:ok, txid, _changes} =
      Writer.new()
      |> Writer.allow(User)
      |> Writer.apply(mutations, Chat.Repo, format: Format.TanstackDB)

    json(conn, %{txid: Integer.to_string(txid)})
  end

  def ingest(conn, _params) do
    send_resp(conn, 400, "invalid_payload")
  end
end
