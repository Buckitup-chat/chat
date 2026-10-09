defmodule Chat.Test.ReadGateHelpers do
  @moduledoc "Trust-mode setup, vouching and read-session helpers for read gating tests."

  import Chat.Test.ReviewFixtures, only: [insert_user_card: 1, sign_with_key: 2]
  import ExUnit.Callbacks, only: [on_exit: 1]
  import Phoenix.ConnTest
  import Plug.Conn

  alias Chat.AdminDb
  alias Chat.Challenge
  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.User
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.DeviceId

  @endpoint ChatWeb.Endpoint

  @doc "Sets gate mode (and optionally the owner) in AdminDB, restoring both on exit."
  def put_gate(mode, owner_card \\ nil) do
    prev_mode = AdminDb.get(:pq_gate_mode)
    prev_owner = AdminDb.get(:pq_admin)

    AdminDb.put(:pq_gate_mode, mode)
    AdminDb.put(:pq_admin, owner_card && Map.take(owner_card, [:user_hash, :sign_pkey]))

    on_exit(fn ->
      AdminDb.put(:pq_gate_mode, prev_mode)
      AdminDb.put(:pq_admin, prev_owner)
    end)
  end

  @doc "Generates a PQ identity and inserts its user card; returns `{identity, card}`."
  def identity_with_card(name) do
    identity = User.generate_pq_identity(name)
    {identity, insert_user_card(identity)}
  end

  @doc "Signs and upserts a vouch token scoped to `device.<id>.<scope_suffix>`; crashes unless stored."
  def vouch(issuer_identity, issuer_hash, subject_hash, scope_suffix) do
    {:ok, _} =
      %VouchToken{
        kind: "device.#{DeviceId.id()}.#{scope_suffix}",
        issuer_hash: issuer_hash,
        subject_hash: subject_hash,
        owner_timestamp: System.os_time(:millisecond),
        deleted_flag: false
      }
      |> sign_with_key(issuer_identity.sign_skey)
      |> Map.from_struct()
      |> then(&VouchToken.create_changeset(%VouchToken{}, &1))
      |> VouchTokenData.upsert_vouch_token()
  end

  @doc "Stores a fresh challenge, signs it and POSTs a read-session request; returns the conn."
  def post_read_session(conn, user_hash, shape, sign_skey) do
    {challenge_id, challenge} = Challenge.store()
    signature = challenge |> EnigmaPq.sign(sign_skey) |> Base.encode64(padding: false)

    post(conn, "/electric/v1/read_session", %{
      user_hash: user_hash,
      shape: shape,
      challenge_id: challenge_id,
      signature: signature
    })
  end

  @doc "Opens a read session asserting HTTP 200; returns the session token."
  def open_read_session!(conn, user_hash, shape, sign_skey) do
    %{status: 200, resp_body: body} = post_read_session(conn, user_hash, shape, sign_skey)
    body |> Jason.decode!() |> Map.fetch!("token")
  end

  @doc "Adds a bearer `authorization` header."
  def with_bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)
end
