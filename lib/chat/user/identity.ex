defmodule Chat.User.Identity do
  @moduledoc "User Identity to be stored on user device"

  @derive {Inspect, only: [:name]}
  defstruct [:name, :priv_key]

  def create(name) do
    %__MODULE__{
      name: name,
      priv_key: generate_key()
    }
  end

  def pub_key(%__MODULE__{} = identitiy) do
    X509.PublicKey.derive(identitiy.priv_key)
  end

  defp generate_key do
    X509.PrivateKey.new_rsa(2048)
  end
end
