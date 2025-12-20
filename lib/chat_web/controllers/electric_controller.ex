defmodule ChatWeb.ElectricController do
  use ChatWeb, :controller

  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Schemas.User
  alias Phoenix.Sync.Writer
  alias Phoenix.Sync.Writer.Format

  def ingest(conn, params) do
    with {_, %{"mutations" => mutations}} <- {:correct_params, params},
         {_, true} <- {:is_mutation_list, is_list(mutations)},
         {:ok, mutations} <- normalize_mutations(mutations),
         {:ok, txid, _changes} <-
           Writer.new()
           |> Writer.allow(User)
           |> Writer.apply(mutations, repo(), format: Format.TanstackDB) do
      json(conn, %{txid: txid})
    else
      error -> handle_ingest_error(conn, error)
    end
  end

  defp normalize_mutations(mutations) do
    mutations
    |> Enum.reduce_while({:ok, []}, fn mutation, {:ok, acc} ->
      case normalize_mutation(mutation) do
        {:ok, mutation} -> {:cont, {:ok, [mutation | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, mutations} -> {:ok, Enum.reverse(mutations)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_mutation(%{} = mutation) do
    with {:ok, mutation} <- normalize_pub_key_in(mutation, ["modified", "pub_key"]),
         {:ok, mutation} <- normalize_pub_key_in(mutation, ["changes", "pub_key"]),
         {:ok, mutation} <- normalize_pub_key_in(mutation, ["original", "pub_key"]) do
      {:ok, mutation}
    end
  end

  defp normalize_mutation(_), do: {:error, "invalid_payload"}

  defp normalize_pub_key_in(map, path) do
    case get_in(map, path) do
      nil ->
        {:ok, map}

      value ->
        case normalize_pub_key(value) do
          {:ok, decoded} -> {:ok, put_in(map, path, decoded)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp normalize_pub_key(key) do
    case key do
      "\\x" <> hex -> Base.decode16(hex, case: :mixed)
      "0x" <> hex -> Base.decode16(hex, case: :mixed)
      str when is_binary(str) -> {:ok, str}
      _ -> :error
    end
    |> case do
      :error -> {:error, "invalid_pub_key"}
      x -> x
    end
  end

  defp handle_ingest_error(conn, error) do
    case error do
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
