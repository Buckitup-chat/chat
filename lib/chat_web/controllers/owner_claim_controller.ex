defmodule ChatWeb.OwnerClaimController do
  @moduledoc """
  A person signed in on this device claims it while it has no owner, by proving
  the key of their card stored here (see `Chat.Pq.OwnerBootstrap`).
  """

  use ChatWeb, :controller

  alias Chat.Pq.OwnerBootstrap
  alias Chat.Pq.ReadGate

  def create(conn, params) do
    with {:ok, card} <-
           ReadGate.prove_key(params["user_hash"], params["challenge_id"], params["signature"]),
         result when result in [:registered, :already_registered] <-
           OwnerBootstrap.maybe_register_card(card) do
      json(conn, %{admin: owner_hash()})
    else
      :not_eligible -> conn |> put_status(403) |> json(%{error: "not_eligible"})
      {:error, reason} -> conn |> put_status(401) |> json(%{error: Atom.to_string(reason)})
    end
  end

  def options(conn, _params), do: send_resp(conn, 204, "")

  defp owner_hash do
    case OwnerBootstrap.owner() do
      %{user_hash: user_hash} -> user_hash
      _ -> nil
    end
  end
end
