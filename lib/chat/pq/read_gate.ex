defmodule Chat.Pq.ReadGate do
  @moduledoc """
  Read (shape sync) gating for `trust` mode.

  `open_session/4` proves possession (PoP over a one-time challenge) and checks
  the vouch chain for `device.<id>.storage.read.<shape>` once, then issues a
  per-shape `Chat.Pq.ReadSession` token. Reads only check the token.
  """

  alias Chat.AdminDb
  alias Chat.Challenge
  alias Chat.Data.Shapes
  alias Chat.Data.User, as: UserData
  alias Chat.Data.VouchToken
  alias Chat.DeviceId
  alias Chat.Pq.OwnerBootstrap
  alias Chat.Pq.ReadSession

  @doc "Reads need a session only in `trust` mode once an owner is registered."
  def enforced? do
    AdminDb.get(:pq_gate_mode) == :trust and OwnerBootstrap.owner() != nil
  end

  def max_depth, do: VouchToken.default_max_depth()

  @doc """
  Returns `{:ok, token, shape_name}` or `{:error, reason}` where reason is one of
  `:unknown_shape`, `:invalid_challenge`, `:unknown_user`, `:invalid_signature`,
  `:not_in_trust_chain`.
  """
  def open_session(user_hash, shape, challenge_id, signature_b64) do
    with {:ok, shape_name} <- resolve_shape(shape),
         {:ok, challenge} <- consume_challenge(challenge_id),
         {:ok, sign_pkey} <- fetch_sign_pkey(user_hash),
         :ok <- verify_signature(challenge, signature_b64, sign_pkey),
         :ok <- check_chain(user_hash, shape_name) do
      {:ok, ReadSession.issue(user_hash, shape_name), shape_name}
    end
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

  defp consume_challenge(challenge_id) when is_binary(challenge_id) do
    case Challenge.get(challenge_id) do
      challenge when is_binary(challenge) -> {:ok, challenge}
      _ -> {:error, :invalid_challenge}
    end
  end

  defp consume_challenge(_), do: {:error, :invalid_challenge}

  defp fetch_sign_pkey(user_hash) when is_binary(user_hash) do
    case UserData.get_card(user_hash) do
      %{deleted_flag: false, sign_pkey: sign_pkey} -> {:ok, sign_pkey}
      _ -> {:error, :unknown_user}
    end
  rescue
    Ecto.Query.CastError -> {:error, :unknown_user}
  end

  defp fetch_sign_pkey(_), do: {:error, :unknown_user}

  defp verify_signature(challenge, signature_b64, sign_pkey) when is_binary(signature_b64) do
    with {:ok, signature} <- Base.decode64(signature_b64, padding: false),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, :invalid_signature}
    end
  rescue
    ErlangError -> {:error, :invalid_signature}
  end

  defp verify_signature(_, _, _), do: {:error, :invalid_signature}

  defp read_scope(shape_name), do: "device.#{DeviceId.id()}.storage.read.#{shape_name}"
end
