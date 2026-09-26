defmodule Chat.Pq.ServerIdentity do
  @moduledoc "Server PQ identity — generates keypair on first boot, persists in AdminDB."

  use GenServer
  use Toolbox.OriginLog

  alias Chat.AdminDb
  alias Chat.Data.Types.UserHash

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get do
    GenServer.call(__MODULE__, :get)
  end

  def sign_pkey, do: get().sign_pkey

  def user_hash do
    sign_pkey()
    |> EnigmaPq.hash()
    |> UserHash.from_binary()
  end

  @impl true
  def init(_opts) do
    identity = load_or_generate()
    {:ok, identity}
  end

  @impl true
  def handle_call(:get, _from, identity) do
    {:reply, identity, identity}
  end

  defp load_or_generate do
    case AdminDb.get(:pq_server_identity) do
      nil ->
        identity = EnigmaPq.generate_identity()
        AdminDb.put(:pq_server_identity, identity)
        AdminDb.put_new(:pq_gate_mode, :open)
        log("Server identity generated", :info)
        identity

      identity ->
        identity
    end
  end
end
