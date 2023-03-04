defmodule NaiveApi.Schema do
  @moduledoc """
  NaiveApi GraphQL schema
  """
  use Absinthe.Schema

  import_types(NaiveApi.Schema.Types)

  query do
    field :hello, :string do
      resolve(fn _, _, _ -> {:ok, "Hello Wold"} end)
    end

    @desc "List all users excluding requesting one"
    field :user_list, list_of(non_null(:card)) do
      arg(:my_public_key, :public_key |> non_null)
    end

    @desc """
    Reads chat messages.

    `before` and `amount` are in indexes. One index contains at least one message.
    If `before` omitted, most recent messaages will be returned.
    If `amount` omitted, messages in 20 indexes will be returned.
    """
    field :chat_read, list_of(:message |> non_null) do
      arg(:peer_public_key, non_null(:public_key))
      arg(:my_keypair, non_null(:input_key_pair))
      arg(:before, :integer)
      arg(:amount, :integer)
    end

    @desc """
    Reads room messages.

    `before` and `amount` are in indexes. One index contains at least one message.
    If `before` omitted, most recent messaages will be returned.
    If `amount` omitted, messages in 20 indexes will be returned.
    """
    field :room_read, list_of(:message |> non_null) do
      arg(:room_keypair, non_null(:input_key_pair))
      arg(:my_keypair, non_null(:input_key_pair))
      arg(:before, :integer)
      arg(:amount, :integer)
    end
  end

  mutation do
    @desc """
    Registers new user in the system. Providing unique keypair.

    There is no uniqeness restriction on the name.
    The system references users by their public_key 
    """
    field :user_sign_up, non_null(:identity) do
      arg(:name, non_null(:string))
    end

    @desc """
    Sends text message in the room.

    There is no limit on `text` length.
    `timestamp` is unixtime in seconds. Will use system time if `timestamp` omitted.  
    """
    field :room_send_text, non_null(:message_reference) do
      arg(:room_keypair, non_null(:input_key_pair))
      arg(:my_keypair, non_null(:input_key_pair))
      arg(:text, :string |> non_null)
      arg(:timestamp, :integer)
    end
  end
end
