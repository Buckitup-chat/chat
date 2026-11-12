defmodule Chat.Storage.LinkRunner do
  @moduledoc """
  Owns one `Chat.Storage.Link`.

  `bootstrap/1` and `replicate/1` run the link's operations in this process. While
  replicating it polls the subscription lag into `Chat.Storage.Links`. Whatever
  ends the process (eject, crash, restart, plan step `:stop`) cleans up through the
  same path: `on_exit` → `Link.stop/1`.

  Options: `link:` (required), `lag_ms:` (lag poll interval, default 5 s).

  See `docs/pq/reqs/files/pq_storage_units.proposed.md` §2.7.4.
  """

  use GracefulGenServer

  alias Chat.Storage.Link
  alias Chat.Storage.Links

  @lag_ms 5_000

  @spec bootstrap(GenServer.server()) :: :ok | {:partial, map()} | {:error, term()}
  def bootstrap(runner), do: GenServer.call(runner, :bootstrap, :infinity)

  @spec replicate(GenServer.server()) :: :ok | {:error, term()}
  def replicate(runner), do: GenServer.call(runner, :replicate, :infinity)

  @spec link(GenServer.server()) :: Link.t()
  def link(runner), do: GenServer.call(runner, :link)

  @impl GracefulGenServer
  def on_init(opts) do
    %Link{} = link = Keyword.fetch!(opts, :link)
    Links.put_status(link, :idle)
    %{link: link, lag_ms: Keyword.get(opts, :lag_ms, @lag_ms), replicating?: false}
  end

  @impl GenServer
  def handle_call(:bootstrap, _from, state), do: {:reply, Link.bootstrap(state.link), state}

  def handle_call(:replicate, _from, state) do
    case Link.replicate(state.link) do
      :ok ->
        unless state.replicating?, do: schedule_lag(state)
        {:reply, :ok, %{state | replicating?: true}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:link, _from, state), do: {:reply, state.link, state}

  @impl GracefulGenServer
  def on_msg(:lag, %{link: link} = state) do
    case Link.lag(link) do
      {:ok, bytes} -> Links.put_lag(link, bytes)
      {:error, _reason} -> :ok
    end

    schedule_lag(state)
    {:noreply, state}
  end

  @impl GracefulGenServer
  def on_exit(_reason, %{link: link}), do: Link.stop(link)

  defp schedule_lag(state), do: Process.send_after(self(), :lag, state.lag_ms)
end
