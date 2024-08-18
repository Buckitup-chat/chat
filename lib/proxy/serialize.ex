defmodule Proxy.Serialize do
  @moduledoc "Serialization and deserialization of Erlang terms"

  def serialize(term) do
    :erlang.term_to_binary(term, [:compressed])
  end

  def deserialize(binary) do
    Plug.Crypto.non_executable_binary_to_term(binary, [:safe])
  end

  def deserialize_with_atoms(binary) do
    Plug.Crypto.non_executable_binary_to_term(binary)
  end
end
