defmodule NaiveApi.Schema.Types do
  @moduledoc """
  Basic types for NaiveApi
  """
  use Absinthe.Schema.Notation

  alias NaiveApi.Types.Bitstring

  ###################
  #  Scalars
  ###################

  scalar :private_key, description: "Private key representation" do
    parse(&Bitstring.parse_33/1)
    serialize(&Bitstring.serialize_33/1)
  end

  scalar :public_key, description: "Public key representation" do
    parse(&Bitstring.parse_32/1)
    serialize(&Bitstring.serialize_32/1)
  end

  scalar :file_key, description: "File key" do
    parse(&Bitstring.parse_32/1)
    serialize(&Bitstring.serialize_32/1)
  end

  scalar :bitstring, description: "Any binary data" do
    parse(&Bitstring.parse/1)
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
    field(:keys, :key_pair |> non_null)
  end

  @desc "User or Room card"
  object :card do
    field(:name, :string |> non_null)
    field(:public_key, :public_key |> non_null)
  end

  @desc "Message reference"
  object :message_reference do
    field(:index, :integer |> non_null)
    field(:id, :id |> non_null)
  end

  # enum :file_content_type do
  #   value(:file)
  #   value(:image)
  #   value(:video)
  #   value(:audio)
  # end

  # object :room_invite_content do
  #   field(:room_card, :card |> non_null)
  #   field(:invitation, :bitstring |> non_null)
  # end

  # object :file_content do
  #   field(:url, :string |> non_null)
  #   field(:type, :file_content_type |> non_null)
  #   field(:size_bytes, :integer |> non_null)
  #   field(:initial_name, :string |> non_null)
  # end

  # union :content do
  #   types([:file_content, :room_invite_content, :string])
  # end

  # object :msg do
  #   # field(:author, :card |> not_null)
  #   # field(:content, :content |> not_null)
  #   # field(:timestamp, :integer |> not_null)
  #   # field(:index, :integer |> not_null)
  #   field(:id, not_null(:id))
  # end

  ###################
  #  Input objects
  ###################

  @desc "Key pair"
  input_object :input_key_pair do
    field(:private_key, non_null(:private_key))
    field(:public_key, non_null(:public_key))
  end
end
