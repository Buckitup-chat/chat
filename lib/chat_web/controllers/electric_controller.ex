defmodule ChatWeb.ElectricController do
  use ChatWeb, :controller

  alias Chat.Data.Schemas.User
  alias Phoenix.Sync.Writer
  alias Phoenix.Sync.Writer.Format

  def ingest(conn, %{"mutations" => mutations}) when is_list(mutations) do
    with {:ok, mutations} <- normalize_mutations(mutations),
         {:ok, txid, _changes} <-
           Writer.new()
           |> Writer.allow(User)
           |> Writer.apply(mutations, Chat.Repo, format: Format.TanstackDB) do
      json(conn, %{txid: txid})
    else
      error ->
        handle_ingest_error(conn, error)
    end
  end

  def ingest(conn, _params) do
    send_resp(conn, 400, "invalid_payload")
  end

  defp handle_ingest_error(
         conn,
         {:error, _failed_operation, %Ecto.Changeset{} = changeset, _changes}
       ) do
    {status, body} =
      if pub_key_unique_conflict?(changeset),
        do: {:conflict, %{error: "pub_key_taken"}},
        else:
          {:unprocessable_entity,
           %{error: "validation_failed", details: changeset_errors(changeset)}}

    conn
    |> put_status(status)
    |> json(body)
  end

  defp handle_ingest_error(
         conn,
         {:error, _failed_operation, %Writer.Error{message: message}, _changes}
       )
       when is_binary(message) do
    send_resp(conn, 400, message)
  end

  defp handle_ingest_error(conn, {:error, reason}) when is_binary(reason) do
    send_resp(conn, 400, reason)
  end

  defp handle_ingest_error(conn, _error) do
    send_resp(conn, 400, "invalid_payload")
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

  defp normalize_pub_key("\\x" <> hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, "invalid_pub_key"}
    end
  end

  defp normalize_pub_key("0x" <> hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, "invalid_pub_key"}
    end
  end

  defp normalize_pub_key(value) when is_binary(value), do: {:ok, value}
  defp normalize_pub_key(_), do: {:error, "invalid_pub_key"}
end
