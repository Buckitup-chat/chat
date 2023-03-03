defmodule NaiveApi.Schema.Types do
  @moduledoc """
  Basic types for NaiveApi
  """
  use Absinthe.Schema.Notation

  object :key_pair do
    field(:private_key, :string)
    field(:public_key, :string)
  end
end
