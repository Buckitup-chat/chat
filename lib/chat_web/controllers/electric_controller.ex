defmodule ChatWeb.ElectricController do
  use ChatWeb, :controller

  import Chat.Db, only: [repo: 0]

  alias Chat.Challenge
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.User, as: UserData
  alias ChatWeb.Utils.IngestUtil
  alias EnigmaPq
  alias Phoenix.Sync.Writer
  alias Phoenix.Sync.Writer.Format
  alias Phoenix.Sync.Writer.Operation

  def ingest(conn, params) do
    binary_suffixes = ~w[_pkey _cert _hash]

    with {_, %{"mutations" => mutations}} <- {:correct_params, params},
         {_, true} <- {:is_mutation_list, is_list(mutations)},
         {:ok, mutations} <- IngestUtil.decode_mutation_fields(mutations, binary_suffixes),
         {:ok, user_pop_context} <- user_pop_context(conn),
         {:ok, txid, _changes} <-
           Writer.new()
           |> Writer.allow(UserCard,
             accept: [:insert, :update, :delete],
             check: &check_user_card_operation(&1, user_pop_context),
             insert: [validate: &validate_user_card_insert/2],
             update: [validate: &validate_user_card_update/2],
             delete: [validate: &validate_user_card_delete/2]
           )
           |> Writer.apply(mutations, repo(), format: Format.TanstackDB) do
      json(conn, %{txid: txid})
    else
      error -> handle_ingest_error(conn, error)
    end
  end

  defp user_pop_context(conn) do
    challenge_id = get_req_header(conn, "x-user-challenge-id") |> List.first()
    signature_hex = get_req_header(conn, "x-user-signature") |> List.first()

    with {_, true} <- {:has_headers, is_binary(challenge_id) and is_binary(signature_hex)},
         {:ok, challenge} <- fetch_challenge(challenge_id),
         {:ok, signature} <- decode_hex(signature_hex) do
      {:ok, %{challenge: challenge, signature: signature}}
    else
      {:has_headers, false} -> {:error, {:unauthorized, "Missing x-user challenge headers"}}
      :error -> {:error, {:unauthorized, "Invalid or expired challenge"}}
      _ -> {:error, {:unauthorized, "Invalid x-user signature format"}}
    end
  end

  defp check_user_card_operation(operation, %{challenge: challenge, signature: signature}) do
    case operation do
      %Operation{operation: :insert} ->
        {:ok, sign_pkey} = operation_change(operation, "sign_pkey")
        true = EnigmaPq.verify(challenge, signature, sign_pkey)
        :ok
    end
  rescue
    _ -> {:error, "Invalid operation"}
  end

  defp validate_user_card_update(card, changes), do: UserCard.update_name_changeset(card, changes)

  defp validate_user_card_delete(card, _changes), do: card

  defp validate_user_card_insert(card, changes) do
    changeset = UserCard.create_changeset(card, changes)

    with true <- changeset.valid?,
         card_data <- Ecto.Changeset.apply_changes(changeset),
         false <- UserData.valid_card?(card_data) do
      Ecto.Changeset.add_error(changeset, :user_hash, "invalid_user_card_integrity")
    else
      _ -> changeset
    end
  end

  defp operation_change(%Operation{changes: changes}, field) do
    case Map.get(changes, field) || Map.get(changes, String.to_atom(field)) do
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, "Missing #{field} in mutation changes"}
    end
  end

  defp fetch_challenge(challenge_id) do
    case Challenge.get(challenge_id) do
      challenge when is_binary(challenge) -> {:ok, challenge}
      _ -> :error
    end
  end

  defp decode_hex(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bin} -> {:ok, bin}
      _ -> :error
    end
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
