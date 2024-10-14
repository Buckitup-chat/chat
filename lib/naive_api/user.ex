defmodule NaiveApi.User do
  @moduledoc "User resolvers"
  use NaiveApi, :resolver
  alias Chat.Sync.DbBrokers
  alias Chat.User
  alias Chat.User.UsersBroker

  def signup(_, params, _) do
    case params do
      %{keypair: keys, name: name} ->
        Chat.Identity.from_keys(keys) |> Map.put(:name, name)

      %{name: name} ->
        name |> String.trim()
    end
    |> User.login()
    |> tap(&User.register/1)
    |> tap(&UsersBroker.put/1)
    |> tap(fn _ -> DbBrokers.broadcast_refresh() end)
    |> ok()
  end

  def list(_, %{my_public_key: public_key}, _) do
    UsersBroker.list()
    |> Enum.reject(fn %{pub_key: pub_key} -> pub_key == public_key end)
    |> ok()
  end
end
