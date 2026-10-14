defmodule Chat.Pq.ReadGate do
  @moduledoc """
  Read (shape sync) gating for `trust` mode.

  `open_session/4` proves possession (PoP over a one-time challenge) and checks
  the vouch chain for `device.<id>.storage.read.<shape>` once, then issues a
  per-shape `Chat.Pq.ReadSession` token. Reads only check the token.
  """

  alias Chat.AdminDb
  alias Chat.Data.Shapes
  alias Chat.Data.VouchToken
  alias Chat.DeviceId
  alias Chat.Pq.KeyProof
  alias Chat.Pq.OwnerBootstrap
  alias Chat.Pq.ReadSession

  use Toolbox.OriginLog

  @doc "Reads need a session only in `trust` mode once an owner is registered."
  def enforced? do
    AdminDb.get(:pq_gate_mode) == :trust and OwnerBootstrap.owner() != nil
  end

  def max_depth do
    Chat.AdminDb.get(:pq_max_depth) || VouchToken.default_max_depth()
  end

  @doc """
  Returns `{:ok, token, shape_name}` or `{:error, reason}` where reason is one of
  `:unknown_shape`, `:invalid_challenge`, `:unknown_user`, `:invalid_signature`,
  `:not_in_trust_chain`.
  """
  def open_session(user_hash, shape, challenge_id, signature_b64) do
    with {:ok, shape_name} <- resolve_shape(shape),
         {:ok, _card} <- KeyProof.prove(user_hash, challenge_id, signature_b64),
         :ok <- check_chain(user_hash, shape_name) do
      {:ok, ReadSession.issue(user_hash, shape_name), shape_name}
    end
    |> tap(fn
      {:ok, _, _} -> :ok
      {:error, reason} -> log("ReadGate denied #{shape} for #{user_hash}: #{reason}", :warning)
    end)
  end

  def check_chain(user_hash, shape_name) do
    case OwnerBootstrap.owner() do
      nil ->
        :ok

      %{user_hash: ^user_hash} ->
        :ok

      %{user_hash: owner_hash} ->
        owner_hash
        |> VouchToken.chain_distance(user_hash, read_scope(shape_name), max_depth())
        |> case do
          {:ok, _distance} -> :ok
          _ -> {:error, :not_in_trust_chain}
        end
    end
  end

  defp resolve_shape(shape) when is_binary(shape) do
    case Shapes.by_name(shape) do
      nil -> {:error, :unknown_shape}
      shape_mod -> {:ok, shape_mod.shape_name()}
    end
  end

  defp resolve_shape(_), do: {:error, :unknown_shape}

  defp read_scope(shape_name), do: "device.#{DeviceId.id()}.storage.read.#{shape_name}"
end
