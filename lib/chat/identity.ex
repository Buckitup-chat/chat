defmodule Chat.Identity do
  @moduledoc "Identity to be stored on user device. Can be used for User as well as for Room"

  @derive {Inspect, only: [:name]}
  defstruct [:name, :private_key, :public_key]

  def create(name) do
    {private, public} = Enigma.generate_keys()

    %__MODULE__{
      name: name,
      private_key: private,
      public_key: public
    }
  end

  def pub_key(%__MODULE__{public_key: public}), do: public

  def to_strings(%__MODULE__{name: name, private_key: private, public_key: public}) do
    [name, Base.encode64(private <> public)]
  end

  def from_strings([name, key_str]) do
    key_str
    |> Base.decode64!()
    |> then(fn <<private::binary-size(32), public::binary-size(33)>> ->
      %__MODULE__{
        name: name,
        private_key: private,
        public_key: public
      }
    end)
  end
end

defimpl Enigma.Hash.Protocol, for: Chat.Identity do
  def to_iodata(%Chat.Identity{public_key: public}), do: public
end
