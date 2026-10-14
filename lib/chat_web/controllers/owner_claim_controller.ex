defmodule ChatWeb.OwnerClaimController do
  @moduledoc """
  A person signed in on this device claims it while it has no owner, by proving
  the key of their card stored here (see `Chat.Pq.OwnerBootstrap`).
  """

  use ChatWeb, :controller

  alias Chat.Pq.KeyProof
  alias Chat.Pq.OwnerBootstrap
  alias ChatWeb.Utils.KeyProofResponse

  def create(conn, params) do
    with {:ok, card} <-
           KeyProof.prove(params["user_hash"], params["challenge_id"], params["signature"]),
         result when result in [:registered, :already_registered] <-
           OwnerBootstrap.maybe_register_card(card) do
      json(conn, %{admin: OwnerBootstrap.owner_hash()})
    else
      :not_eligible ->
        conn |> put_status(403) |> json(%{error: "not_eligible"})

      {:error, reason} ->
        {status, body} = KeyProofResponse.of(reason)
        conn |> put_status(status) |> json(body)
    end
  end

  def options(conn, _params), do: send_resp(conn, 204, "")
end
