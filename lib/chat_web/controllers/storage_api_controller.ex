defmodule ChatWeb.StorageApiController do
  use ChatWeb, :controller

  alias Chat.Broker

  @doc """
  Generates a confirmation token for API authentication.

  Returns:
    %{
      token_key: "hex_encoded_token_key",
      token: "hex_encoded_token"
    }
  """
  def confirmation_token(conn, _params) do
    # Generate random token
    token = :crypto.strong_rand_bytes(32)

    # Store the token in the broker and get a token key
    token_key = Broker.store(token)

    # Return the token key and token
    json(conn, %{
      token_key: token_key,
      token: token |> Base.encode64()
    })
  end

  @doc """
  Stores encrypted data.

  Request query parameters:
    - pub_key: The public key (hex encoded)
    - token_key: The token key from confirmation_token
    - signature: Signature of the token (hex encoded)

  Request body:
    %{
      key: "string_key",
      value: "any_value"
    }
  """
  def put(conn, params) do
    with %{"pub_key" => pub_key_hex, "token_key" => token_key, "signature" => signature_hex} <-
           params,
         %{"key" => key_json, "value" => value} <- conn.body_params,
         {:ok, key} <- Jason.decode(key_json),
         {:ok, pub_key} <- Base.decode16(pub_key_hex, case: :lower),
         {:ok, signature} <- Base.decode16(signature_hex, case: :lower),
         token <- Broker.get(token_key),
         false <- is_nil(token) && {:error, "Invalid or expired token key"},
         true <- Enigma.valid_sign?(signature, token, pub_key) || {:error, "Invalid signature"} do
      db_key = {:storage, pub_key, key}
      Chat.Db.put(db_key, value)
      Chat.Db.Copying.await_written_into([db_key], Chat.Db.db())

      json(conn, %{status: "success"})
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: reason})
    end
  end

  @doc """
  Retrieves all stored data for a public key.

  Request query parameters:
    - pub_key: The public key (hex encoded)
    - token_key: The token key from confirmation_token
    - signature: Signature of the token (hex encoded)
  """
  def dump(
        conn,
        %{"pub_key" => pub_key_hex, "token_key" => token_key, "signature" => signature_hex} =
          _params
      ) do
    with {:ok, pub_key} <- Base.decode16(pub_key_hex, case: :lower),
         {:ok, signature} <- Base.decode16(signature_hex, case: :lower),
         token <- Broker.get(token_key),
         false <- is_nil(token) && {:error, "Invalid or expired token key"},
         true <- Enigma.valid_sign?(signature, token, pub_key) || {:error, "Invalid signature"} do
      # Query all data with key pattern {:storage, pub_key, _}
      min_key = {:storage, pub_key, nil}
      max_key = {:storage, pub_key <> "\0", nil}

      values = Chat.Db.list({min_key, max_key})

      # Format the result
      result =
        values
        |> Enum.map(fn {{:storage, _pub_key, payload_key}, payload_value} ->
          %{
            key: payload_key,
            value: payload_value
          }
        end)

      json(conn, result)
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: reason})
    end
  end

  def dump(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: pub_key, token_key, signature"})
  end
end
