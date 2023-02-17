defmodule Chat.Identity do
  @moduledoc "Identity to be stored on user device. Can be used for User as well as for Room"

  alias Chat.Codec

  @derive {Inspect, only: [:name]}
  defstruct [:name, :priv_key]

  def create(name) do
    %__MODULE__{
      name: name,
      priv_key: generate_key()
    }
  end

  def pub_key(%__MODULE__{} = identity) do
    X509.PublicKey.derive(identity.priv_key)
  end

  def to_strings(%__MODULE__{name: name, priv_key: key}) do
    [name, key |> Codec.private_key_to_string()]
  end

  def priv_key_to_string(%__MODULE__{priv_key: key}) do
    Codec.private_key_to_string(key)
  end

  def from_strings([name, key_str]) do
    %__MODULE__{
      name: name,
      priv_key: key_str |> Codec.private_key_from_string()
    }
  end

  defp generate_key do
    X509.PrivateKey.new_rsa(2048)
  end
end
