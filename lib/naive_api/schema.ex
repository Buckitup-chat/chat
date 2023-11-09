defmodule NaiveApi.Schema do
  @moduledoc """
  NaiveApi GraphQL schema
  """
  use Absinthe.Schema

  alias NaiveApi.Chat
  alias NaiveApi.Data
  alias NaiveApi.Room
  alias NaiveApi.Upload
  alias NaiveApi.User

  import_types(NaiveApi.Schema.Types)

  query do
    field :hello, :string do
      resolve(fn _, _, _ -> {:ok, "Hello Wold"} end)
    end

    @desc "List all users excluding requesting one"
    field :user_list, list_of(non_null(:card)) do
      arg(:my_public_key, :public_key |> non_null)
      resolve(&User.list/3)
    end

    @desc """
    Reads chat messages.

    `before` and `amount` are in indexes. One index contains at least one message.
    If `before` omitted, most recent messages will be returned.
    If `amount` omitted, messages in 20 indexes will be returned.
    """
    field :chat_read, list_of(:message |> non_null) do
      arg(:peer_public_key, non_null(:public_key))
      arg(:my_keypair, non_null(:input_key_pair))
      arg(:before, :integer)
      arg(:amount, :integer)
      resolve(&Chat.read/3)
    end

    @desc """
    Reads room messages.

    `before` and `amount` are in indexes. One index contains at least one message.
    If `before` omitted, most recent messages will be returned.
    If `amount` omitted, messages in 20 indexes will be returned.
    """
    field :room_read, list_of(:message |> non_null) |> non_null() do
      arg(:room_keypair, non_null(:input_key_pair))
      arg(:before, :integer)
      arg(:amount, :integer)
      resolve(&Room.read/3)
    end

    @desc """
    Dumps all keys available
    """
    field :data_keys, list_of(:string |> non_null) do
      resolve(&Data.all_keys/2)
    end

    @desc """
    Gets value by key
    """
    field :data_value, :string do
      arg(:key, :string |> non_null)
      resolve(&Data.get_value/2)
    end
  end

  mutation do
    @desc """
    Registers new user in the system. Providing unique keypair.

    There is no uniqueness restriction on the name.
    The system references users by their public_key 
    """
    field :user_sign_up, non_null(:identity) do
      arg(:name, non_null(:string))
      resolve(&User.signup/3)
    end

    @desc "Creates the upload key."
    field :upload_key, non_null(:file_key) do
      arg(:my_keypair, non_null(:input_key_pair))
      arg(:destination, non_null(:input_upload_destination))
      arg(:entry, non_null(:input_upload_entry))
      resolve(&Upload.create_key/3)
    end

    @desc """
    Sends text message in the room.

    There is no limit on `text` length.
    `timestamp` is unixtime in seconds. Will use system time if `timestamp` omitted.  
    """
    field :room_send_text, non_null(:message_reference) do
      arg(:room_keypair, non_null(:input_key_pair))
      arg(:my_keypair, non_null(:input_key_pair))
      arg(:text, non_null(:string))
      arg(:timestamp, :integer)
      resolve(&Room.send_text/3)
    end

    @desc "Send file in the room."
    field :room_send_file, non_null(:message_reference) do
      arg(:room_keypair, non_null(:input_key_pair))
      arg(:my_keypair, non_null(:input_key_pair))
      arg(:upload_key, non_null(:file_key))
      resolve(&Room.send_file/3)
    end
  end
end
