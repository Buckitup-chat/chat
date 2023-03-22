defmodule NaiveApi.User do
  @moduledoc "User resolvers"
  use NaiveApi, :resolver
  alias Chat.User

  def signup(_, %{name: name}, _) do
    name
    |> String.trim()
    |> User.login()
    |> tap(&User.register/1)
    |> ok()
  end

  def list(_, %{my_public_key: public_key}, _) do
    User.list()
    |> Enum.reject(fn %{pub_key: pub_key} -> pub_key == public_key end)
    |> ok()
  end
end
