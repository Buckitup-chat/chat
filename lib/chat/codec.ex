defmodule Chat.Codec do
  @moduledoc "Structures to string or list of string transformation, and vice versa"

  alias X509.PrivateKey
  alias X509.PublicKey

  def private_key_to_string(key) do
    key
    |> PrivateKey.to_der()
    |> Base.encode64()
  end

  def private_key_from_string(string) do
    string
    |> Base.decode64!()
    |> PrivateKey.from_der!()
  end

  def public_key_to_string(key) do
    key
    |> PublicKey.to_der()
    |> Base.encode64()
  end

  def public_key_from_string(string) do
    string
    |> Base.decode64!()
    |> PublicKey.from_der!()
  end
end
