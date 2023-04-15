defmodule NaiveApi.User do
  @moduledoc "User resolvers"
  use NaiveApi, :resolver
  alias Chat.User
  alias Chat.UsersBroker

  def signup(_, %{name: name}, _) do
    name
    |> String.trim()
    |> User.login()
    |> tap(&User.register/1)
    |> tap(&UsersBroker.put/1)
    |> ok()
  end

  def list(_, %{my_public_key: public_key}, _) do
    UsersBroker.list()
    |> Enum.reject(fn %{pub_key: pub_key} -> pub_key == public_key end)
    |> ok()
  end
end
