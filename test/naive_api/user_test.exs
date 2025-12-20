defmodule NaiveApi.UserTest do
  use ChatWeb.DataCase, async: true

  alias NaiveApi.Types.Bitstring

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

  @signup_with_keys_mutation """
    mutation SignUp($name: String!, $keypair: InputKeyPair!) {
      userSignUp(name: $name, keypair: $keypair) {
        name
        keys {
          private_key
          public_key
        }
      }
    }
  """
  test "mutation: userSignUpWithKeys" do
    {some_private_key, some_public_key} = Enigma.generate_keys()

    {:ok,
     %{
       data: %{
         "userSignUp" => %{
           "name" => name,
           "keys" => %{"private_key" => private_key, "public_key" => public_key}
         }
       }
     }} =
      Absinthe.run(@signup_with_keys_mutation, @schema,
        variables: %{
          "name" => "Diego",
          "keypair" => %{
            "public_key" => Bitstring.serialize_33(some_public_key),
            "private_key" => Bitstring.serialize_32(some_private_key)
          }
        }
      )

    assert name == "Diego"

    assert 64 == private_key |> byte_size()
    assert 66 == public_key |> byte_size()

    assert {:ok, some_public_key} == Bitstring.parse_33(public_key)
    assert {:ok, some_private_key} == Bitstring.parse_32(private_key)
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
