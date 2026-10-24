defmodule Chat.ReviewBot.Worker do
  @moduledoc "GenServer for a running review bot. Holds decrypted identity, never exposes secret keys."

  use GenServer, restart: :transient

  import Tools.GenServerHelpers

  alias Chat.Pq.Ingest
  alias Chat.ReviewBot.GarbageCollector
  alias EnigmaPq

  @gc_interval :timer.hours(1)

  def start_link(%{bot_hash: bot_hash} = init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: via(bot_hash))
  end

  def whereis(bot_hash) do
    case Registry.lookup(Chat.ReviewBot.Registry, bot_hash) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def running?(bot_hash), do: whereis(bot_hash) != nil

  def ingest(bot_hash, mutations) do
    GenServer.call(via(bot_hash), {:ingest, mutations})
  end

  def sign(bot_hash, payload) do
    GenServer.call(via(bot_hash), {:sign, payload})
  end

  def info(bot_hash) do
    GenServer.call(via(bot_hash), :info)
  end

  # --- Callbacks ---

  @impl true
  def init(%{bot_hash: bot_hash, origin_hash: origin_hash, identity: identity}) do
    Process.flag(:sensitive, true)

    schedule_gc()

    %{bot_hash: bot_hash, origin_hash: origin_hash, identity: identity}
    |> ok()
  end

  @impl true
  def handle_call({:ingest, mutations}, _from, state) do
    result = Ingest.apply(mutations, Ingest.self_pop(state.identity.sign_skey))
    state |> reply(result)
  end

  def handle_call({:sign, payload}, _from, state) do
    signature = EnigmaPq.sign(payload, state.identity.sign_skey)
    state |> reply(signature)
  end

  def handle_call(:info, _from, state) do
    state |> reply(%{bot_hash: state.bot_hash, origin_hash: state.origin_hash})
  end

  @impl true
  def handle_info(:gc_tick, state) do
    GarbageCollector.run(state.bot_hash, state.origin_hash)
    schedule_gc()
    {:noreply, state}
  end

  defp schedule_gc, do: Process.send_after(self(), :gc_tick, @gc_interval)

  defp via(bot_hash), do: {:via, Registry, {Chat.ReviewBot.Registry, bot_hash}}
end
