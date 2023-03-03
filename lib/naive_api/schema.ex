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

    field :keys, list_of(:key_pair) do
      resolve(fn _, _, _ -> {:ok, []} end)
    end
  end
end
