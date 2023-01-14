defmodule Chat.Upload.StaleUploadsPruner do
  use GenServer

  alias Chat.ChunkedFiles
  alias Chat.Upload.{Upload, UploadIndex}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  def maybe_set_timestamp(timestamp) do
    GenServer.cast(__MODULE__, {:maybe_set_timestamp, timestamp})
  end

  ## Callbacks

  @impl GenServer
  def init(_) do
    {:ok, %{monotonic_time: nil, timestamp: nil}}
  end

  @impl GenServer
  def handle_cast({:maybe_set_timestamp, timestamp}, state) do
    if state.timestamp do
      {:noreply, state}
    else
      {:noreply,
       state
       |> Map.put(:monotonic_time, System.monotonic_time(:second))
       |> Map.put(:timestamp, timestamp), {:continue, :prune}}
    end
  end

  @impl GenServer
  def handle_continue(:prune, state), do: {:noreply, prune(state)}

  @impl GenServer
  def handle_info(:prune, state), do: {:noreply, prune(state)}

  defp prune(%{monotonic_time: monotonic_time, timestamp: timestamp} = state) do
    one_day_ago = timestamp + (System.monotonic_time(:second) - monotonic_time) - 24 * 60 * 60

    UploadIndex.list()
    |> Stream.filter(fn {_key, %Upload{} = upload} ->
      upload.timestamp < one_day_ago
    end)
    |> Enum.each(fn {key, %Upload{} = upload} ->
      ChunkedFiles.delete(upload.key)
      UploadIndex.delete(key)
    end)

    Process.send_after(self(), :prune, :timer.hours(1))

    state
  end
end
