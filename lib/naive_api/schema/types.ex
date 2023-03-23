defmodule NaiveApi.Schema.Types do
  @moduledoc """
  Basic types for NaiveApi
  """
  use Absinthe.Schema.Notation

  alias Absinthe.Blueprint.Input.String
  alias NaiveApi.Message
  alias NaiveApi.Shared
  alias NaiveApi.Types.Bitstring

  ###################
  #  Scalars
  ###################

  scalar :private_key, description: "Private key representation" do
    parse(fn
      %String{value: value} -> Bitstring.parse_32(value)
      _ -> :error
    end)

    serialize(&Bitstring.serialize_32/1)
  end

  scalar :public_key, description: "Public key representation" do
    parse(fn
      %String{value: value} -> Bitstring.parse_33(value)
      _ -> :error
    end)

    serialize(&Bitstring.serialize_33/1)
  end

  scalar :file_key, description: "File key" do
    parse(fn
      %String{value: value} -> Bitstring.parse_32(value)
      _ -> :error
    end)

    serialize(&Bitstring.serialize_32/1)
  end

  scalar :bitstring, description: "Any binary data" do
    parse(fn
      %String{value: value} -> Bitstring.parse(value)
      _ -> :error
    end)

    serialize(&Bitstring.serialize/1)
  end

  ###################
  #  Objects
  ###################

  @desc "Key pair"
  object :key_pair do
    field(:private_key, non_null(:private_key))
    field(:public_key, non_null(:public_key))
  end

  @desc "User or Room Identity"
  object :identity do
    field(:name, :string |> non_null)
    field(:keys, :key_pair |> non_null, resolve: &Shared.resolve_identity_keys/3)
  end

  @desc "User or Room card"
  object :card do
    field(:name, :string |> non_null)
    field(:public_key, :public_key |> non_null, resolve: &Shared.resolve_card_key/3)
  end

  @desc "Message reference"
  object :message_reference do
    field(:index, :integer |> non_null)
    field(:id, :id |> non_null)
  end

  @desc "File content type"
  enum :file_content_type do
    value(:file, description: "Generic file")
    value(:image, description: "Image file")
    value(:video, description: "Video file")
    value(:audio, description: "Audio file")
  end

  @desc "Room invite content"
  object :room_invite_content do
    field(:keys, :key_pair |> non_null)
  end

  @desc "File content"
  object :file_content do
    field(:url, :string |> non_null)
    field(:type, :file_content_type |> non_null)
    field(:size_bytes, :integer |> non_null)
    field(:initial_name, :string |> non_null)
  end

  @desc "Text content"
  object :text_content do
    field(:text, :string |> non_null)
  end

  @desc "Message content"
  union :message_content do
    types([:file_content, :room_invite_content, :text_content])
    resolve_type(fn %{__typename: type}, _ -> type end)
  end

  @desc "Message"
  object :message do
    field(:author, :card |> non_null)
    field(:content, :message_content |> non_null, resolve: &Message.fill_content/3)
    field(:timestamp, :integer |> non_null)
    field(:index, :integer |> non_null)
    field(:id, :id |> non_null)
  end

  ###################
  #  Input objects
  ###################

  @desc "Key pair"
  input_object :input_key_pair do
    field(:private_key, non_null(:private_key))
    field(:public_key, non_null(:public_key))
  end

  @desc "Upload destination"
  input_object :input_upload_destination do
    field(:type, non_null(:upload_destination_type))
    field(:keypair, non_null(:input_key_pair))
  end

  @desc "Upload entry"
  input_object :input_upload_entry do
    field(:client_name, non_null(:string))
    field(:client_type, non_null(:string))
    field(:client_size, non_null(:integer))
    field(:client_relative_path, non_null(:string))
    field(:client_last_modified, non_null(:integer))
  end

  enum :upload_destination_type do
    values([:room, :dialog])
  end
end
