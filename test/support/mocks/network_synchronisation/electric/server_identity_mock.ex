defmodule ChatSupport.Mocks.NetworkSynchronization.Electric.ServerIdentityMock do
  @moduledoc "`Chat.Pq.ServerIdentity` stand-in using the identity put in the process dictionary."

  alias Chat.Data.Types.UserHash

  def put(identity), do: Process.put(__MODULE__, identity)

  def get, do: Process.get(__MODULE__)

  def user_hash do
    %{sign_pkey: sign_pkey} = get()

    sign_pkey |> EnigmaPq.hash() |> UserHash.from_binary()
  end
end
