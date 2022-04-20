defmodule Chat.UserTest do
  use ExUnit.Case, async: false

  alias Chat.User

  test "adding a user should add one to full list" do
    old_count = User.list() |> Enum.count()

    user_key = User.login("new") |> User.register()

    new_count = User.list() |> Enum.count()

    assert new_count - 1 >= old_count

    assert %{name: "new"} = User.by_id(user_key)
  end
end
