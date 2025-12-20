defmodule ChatWeb.StorageApiController do
  use ChatWeb, :controller

  alias Chat.Broker
  alias Chat.Card
  alias Chat.Db
  alias Chat.User

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
    with {:ok, pub_key} <- validate_auth(params),
         %{"key" => key_json, "value" => value} <- conn.body_params,
         {:ok, key} <- Jason.decode(key_json) do
      db_key = {:storage, pub_key, key}
      Db.put(db_key, value)
      Db.Copying.await_written_into([db_key], Db.db())

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
  def dump(conn, params) do
    case validate_auth(params) do
      {:ok, pub_key} ->
        min_key = {:storage, pub_key, nil}
        max_key = {:storage, pub_key <> "\0", nil}

        values = Db.list({min_key, max_key})

        result =
          values
          |> Enum.map(fn {{:storage, _pub_key, payload_key}, payload_value} ->
            %{
              key: payload_key,
              value: payload_value
            }
          end)

        json(conn, result)

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: reason})
    end
  end

  @doc """
  Stores multiple encrypted data items at once.

  Request query parameters:
    - pub_key: The public key (hex encoded)
    - token_key: The token key from confirmation_token
    - signature: Signature of the token (hex encoded)

  Request body:
    [
      {
        key: "string_key",
        value: "any_value"
      },
      ...
    ]
  """
  def put_many(conn, params) do
    with {:ok, pub_key} <- validate_auth(params),
         items when is_list(items) <- Map.get(conn.body_params, "_json") do
      items
      |> Enum.map(fn %{"key" => key, "value" => value} ->
        db_key = {:storage, pub_key, key}
        Db.put(db_key, value)
        db_key
      end)
      |> Db.Copying.await_written_into(Db.db())

      json(conn, %{status: "success", items_saved: length(items)})
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: reason})

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid request format"})
    end
  end

  defp validate_auth(params) do
    with true <-
           match?(%{"pub_key" => _, "token_key" => _, "signature" => _}, params) ||
             {:error, "Invalid request format"},
         {:ok, pub_key} <- params |> Map.get("pub_key") |> Base.decode16(case: :lower),
         {:ok, signature} <- params |> Map.get("signature") |> Base.decode16(case: :lower),
         token <- params |> Map.get("token_key") |> Broker.get(),
         false <- is_nil(token) && {:error, "Invalid or expired token key"},
         true <-
           Enigma.valid_sign?(signature, token, pub_key) || {:error, "Invalid signature"},
         %Card{} <- User.by_id(pub_key) || {:error, "User not found"} do
      {:ok, pub_key}
    end
  end
end
