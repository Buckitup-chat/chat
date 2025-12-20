defmodule ChatWeb.StorageApiControllerTest do
  use ChatWeb.ConnCase, async: true
  use ChatWeb.DataCase

  alias Chat.Db
  alias Chat.User

  test "confirmation_token/2 returns a base64 encoded version of token in Chat.Broker", %{
    conn: conn
  } do
    {token_key, digest} = get_confirmation_token(conn)

    assert digest == Chat.Broker.get(token_key)
  end

  test "with put I can store some info under my pubkey namespace", %{conn: conn} do
    {token_key, digest} = get_confirmation_token(conn)
    {private_key, public_key_bin} = generate_user_keys()

    payload_key = ["test_payload", System.unique_integer([:positive])]

    payload_value = %{
      "message" => "store this securely!",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    conn_put =
      put_payload(
        conn,
        token_key,
        digest,
        public_key_bin,
        payload_key,
        payload_value,
        private_key
      )

    assert %{"status" => "success"} = json_response(conn_put, 200)

    db_key = {:storage, public_key_bin, payload_key}

    assert payload_value == Db.get(db_key), "Expected DB value to match payload"

    Db.delete(db_key)
  end

  test "with put_many I can store multiple items under my pubkey namespace", %{conn: conn} do
    {private_key, public_key_bin} = generate_user_keys()

    items = [
      {["test_payload_1", System.unique_integer([:positive])],
       %{
         "message" => "store this securely! #1",
         "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
       }},
      {["test_payload_2", System.unique_integer([:positive])],
       %{
         "message" => "store this securely! #2",
         "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
       }}
    ]

    # Create items to save
    items_json =
      items
      |> Enum.map(fn {key, value} ->
        %{"key" => key, "value" => value}
      end)

    {token_key, digest} = get_confirmation_token(conn)

    # Call put_many endpoint
    conn_put =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        Routes.storage_api_path(conn, :put_many,
          pub_key: public_key_bin |> Base.encode16(case: :lower),
          token_key: token_key,
          signature: digest |> Enigma.sign(private_key) |> Base.encode16(case: :lower)
        ),
        Jason.encode!(items_json)
      )

    # Assert successful response
    assert %{"status" => "success", "items_saved" => 2} = json_response(conn_put, 200)

    # Verify items were stored correctly
    items
    |> Enum.each(fn {key, value} ->
      db_key = {:storage, public_key_bin, key}
      assert value == Db.get(db_key), "Expected DB value to match payload"
      Db.delete(db_key)
    end)
  end

  test "with dump I can retrieve all info stored under my pubkey namespace", %{conn: conn} do
    {private_key, public_key_bin} = generate_user_keys()

    p1_key = ["p1", System.unique_integer([:positive])]
    p2_key = ["p0", System.unique_integer([:positive])]

    p1_value = %{
      "message" => "store this securely!",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    p2_value = %{
      "message" => "store this securely!",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {token_key, digest} = get_confirmation_token(conn)
    put_payload(conn, token_key, digest, public_key_bin, p1_key, p1_value, private_key)

    {token_key, digest} = get_confirmation_token(conn)
    put_payload(conn, token_key, digest, public_key_bin, p2_key, p2_value, private_key)

    {token_key, digest} = get_confirmation_token(conn)

    conn_dump =
      get(
        conn,
        Routes.storage_api_path(conn, :dump,
          pub_key: public_key_bin |> Base.encode16(case: :lower),
          token_key: token_key,
          signature: digest |> Enigma.sign(private_key) |> Base.encode16(case: :lower)
        )
      )

    response = json_response(conn_dump, 200)

    assert %{
             "key" => p1_key,
             "value" => p1_value
           } in response

    assert %{
             "key" => p2_key,
             "value" => p2_value
           } in response

    Db.delete({:storage, public_key_bin, p1_key})
    Db.delete({:storage, public_key_bin, p2_key})
  end

  defp get_confirmation_token(conn) do
    conn = get(conn, Routes.storage_api_path(conn, :confirmation_token))
    assert %{"token_key" => token_key, "token" => b64_token_from_api} = json_response(conn, 200)

    digest = Base.decode64!(b64_token_from_api)

    {token_key, digest}
  end

  defp put_payload(
         conn,
         token_key,
         digest,
         public_key_bin,
         payload_key,
         payload_value,
         private_key
       ) do
    post(
      conn,
      Routes.storage_api_path(conn, :put,
        pub_key: public_key_bin |> Base.encode16(case: :lower),
        token_key: token_key,
        signature: digest |> Enigma.sign(private_key) |> Base.encode16(case: :lower)
      ),
      %{
        "key" => payload_key |> Jason.encode!(),
        "value" => payload_value
      }
    )
  end

  defp generate_user_keys do
    identity = User.login("test_user") |> tap(&User.register/1)

    Db.Copying.await_written_into([{:users, identity.public_key}], Db.db())

    {identity.private_key, identity.public_key}
  end
end
