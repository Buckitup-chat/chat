defmodule ChatWeb.ElectricController do
  use ChatWeb, :controller

  import Chat.Db, only: [repo: 0]

  alias Chat.Challenge
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.User.Validation, as: UserValidation
  alias ChatWeb.Utils.IngestUtil
  alias Phoenix.Sync.Writer
  alias Phoenix.Sync.Writer.Format

  def ingest(conn, params) do
    binary_suffixes = ~w[_pkey _cert _hash]

    with {_, %{"mutations" => mutations}} <- {:correct_params, params},
         {_, true} <- {:is_mutation_list, is_list(mutations)},
         {:ok, mutations} <- IngestUtil.decode_mutation_fields(mutations, binary_suffixes),
         {:ok, user_pop_context} <- user_pop_context(params),
         {:ok, txid, _changes} <-
           Writer.new()
           |> Writer.allow(UserCard,
             accept: [:insert, :update, :delete],
             check: &UserValidation.user_card_allowed(&1, user_pop_context),
             validate: &UserValidation.user_card_validate/3
           )
           |> Writer.allow(UserStorage,
             accept: [:insert, :update, :delete],
             check: &UserValidation.user_storage_allowed(&1, user_pop_context),
             validate: &UserValidation.user_storage_validate/3
           )
           |> Writer.apply(mutations, repo(), format: Format.TanstackDB) do
      json(conn, %{txid: txid})
    else
      error -> handle_ingest_error(conn, error)
    end
  end

  defp user_pop_context(params) do
    {challenge_id, signature_encoded} = pop_from_body(params)

    with {_, true} <- {:has_auth, is_binary(challenge_id) and is_binary(signature_encoded)},
         {:ok, challenge} <- fetch_challenge(challenge_id),
         {:ok, signature} <- decode_signature(signature_encoded) do
      {:ok, %{challenge: challenge, signature: signature}}
    else
      {:has_auth, false} -> {:error, {:unauthorized, "Missing user PoP auth"}}
      :error -> {:error, {:unauthorized, "Invalid or expired challenge"}}
      _ -> {:error, {:unauthorized, "Invalid user signature format"}}
    end
  end

  defp pop_from_body(%{"auth" => %{"challenge_id" => challenge_id, "signature" => signature}})
       when is_binary(challenge_id) and is_binary(signature) do
    {challenge_id, signature}
  end

  defp pop_from_body(_params), do: {nil, nil}

  defp fetch_challenge(challenge_id) do
    case Challenge.get(challenge_id) do
      challenge when is_binary(challenge) -> {:ok, challenge}
      _ -> :error
    end
  end

  defp decode_signature(signature_encoded) do
    Base.decode64(signature_encoded, padding: false)
  end

  defp handle_ingest_error(conn, error) do
    case error do
      {:error, {:unauthorized, msg}} when is_binary(msg) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: msg})

      {:error, {:bad_request, msg}} when is_binary(msg) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: msg})

      {:error, _, %Ecto.Changeset{} = changeset, _} ->
        {status, body} =
          if pub_key_unique_conflict?(changeset),
            do: {:conflict, %{error: "pub_key_taken"}},
            else:
              {:unprocessable_entity,
               %{error: "validation_failed", details: changeset_errors(changeset)}}

        conn
        |> put_status(status)
        |> json(body)

      {:error, _, %Writer.Error{message: msg}, _} when is_binary(msg) ->
        send_resp(conn, 400, msg)

      {:error, reason} when is_binary(reason) ->
        send_resp(conn, 400, reason)

      _ ->
        send_resp(conn, 400, "invalid_payload")
    end
  end

  defp pub_key_unique_conflict?(%Ecto.Changeset{} = changeset) do
    case Keyword.fetch(changeset.errors, :pub_key) do
      {:ok, {msg, opts}} ->
        msg == "has already been taken" && Keyword.get(opts, :constraint) == :unique

      :error ->
        false
    end
  end

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn
        {key, value}, acc when is_binary(acc) ->
          String.replace(acc, "%{#{key}}", to_string(value))

        {_key, _value}, acc ->
          acc
      end)
    end)
  end
end
