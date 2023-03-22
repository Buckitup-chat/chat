defmodule NaiveApi.UserTest do
  use ExUnit.Case, async: true

  @schema NaiveApi.Schema
  @signup_mutation """
    mutation SignUp($name: String!) { 
      userSignUp(name: $name) {
        name
        keys {
          private_key
          public_key
        }
      }
    }
  """
  test "mutation: userSignUp" do
    {:ok,
     %{
       data: %{
         "userSignUp" => %{
           "name" => name,
           "keys" => %{"private_key" => private_key, "public_key" => public_key}
         }
       }
     }} = Absinthe.run(@signup_mutation, @schema, variables: %{"name" => "Diego"})

    assert name == "Diego"
    assert 64 == private_key |> byte_size()
    assert 66 == public_key |> byte_size()
  end

  @list_query """
    query userLists($myPublicKey: PublicKey!) { 
      userList(myPublicKey: $myPublicKey) {
        name
        public_key
      }
    }
  """
  test "query: userList" do
    {:ok, %{data: %{"userSignUp" => %{"keys" => %{"public_key" => _}}}}} =
      Absinthe.run(@signup_mutation, @schema, variables: %{"name" => "Diego"})

    {:ok, %{data: %{"userSignUp" => %{"keys" => %{"public_key" => my_public_key}}}}} =
      Absinthe.run(@signup_mutation, @schema, variables: %{"name" => "Bob"})

    {:ok, %{data: %{"userList" => user_list}}} =
      Absinthe.run(@list_query, @schema, variables: %{"myPublicKey" => my_public_key})

    refute Enum.any?(user_list, fn %{"public_key" => key} -> key == my_public_key end)
  end
end
