defmodule Chat.NetworkSynchronization.RetrievalTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.Db.Copying
  alias Chat.NetworkSynchronization.Retrieval

  defmodule DbBrokersMock do
    def refresh, do: :called
  end

  rewire(Retrieval, [{Chat.Sync.DbBrokers, DbBrokersMock}])

  setup_all [:create_user]

  test "error on getting keys" do
    assert {:error, "Wrong URL"} = get_keys_by("")
    assert {:error, "URL is unreachable"} = get_keys_by("123")
    assert {:error, "Not an API endpoint"} = get_keys_by("http://google.com")

    assert {:error, "API error"} =
             get_keys_by("https://swapi-graphql.netlify.app/.netlify/functions/index")
  end

  test "list on getting keys from correct url", %{user: user_pub_key} do
    assert {:ok, keys} = get_keys_by(ChatWeb.Endpoint.url() <> "/naive_api/")
    assert Enum.any?(keys, fn key -> key == {:users, user_pub_key} end)
  end

  test "get and save correct key content", %{user: pub_key} do
    key = {:users, pub_key}
    assert :ok = get_value_by(ChatWeb.Endpoint.url() <> "/naive_api/", key)
  end

  test "get bad content", %{user: pub_key} do
    key = {:users_wrong_prefix, pub_key}
    refute :ok == get_value_by(ChatWeb.Endpoint.url() <> "/naive_api/", key)
  end

  test "reject", %{user: pub_key} do
    key = {:users, pub_key}
    assert [] = reject_known([key])
  end

  test "finalize works" do
    assert :called = Retrieval.finalize()
  end

  test "special helper to make a sync" do
    assert :ok = Retrieval.all_from(ChatWeb.Endpoint.url() <> "/naive_api/")
  end

  defp get_keys_by(url), do: Retrieval.remote_keys(url)
  defp get_value_by(url, key), do: Retrieval.retrieve_key(url, key)
  defp reject_known(keys), do: Retrieval.reject_known(keys)

  defp create_user(_) do
    user = Chat.User.login("Test user") |> Chat.User.register()
    Copying.await_written_into([{:users, user}], Chat.Db.db())

    %{user: user}
  end
end
