defmodule Chat.Upload.UploadStatus do
  use GenServer

  @type key :: String.t()
  @type status :: :active | :inactive

  @spec child_spec(Keyword.t()) :: map()
  def child_spec(opts) do
    key = Keyword.get(opts, :key)
    status = Keyword.get(opts, :status)

    %{
      id: get_name(key),
      start: {__MODULE__, :start_link, [key, status]},
      shutdown: 10_000,
      restart: :transient
    }
  end

  @spec start_link(key(), status()) :: {:ok, pid} | :ignore
  def start_link(key, status) do
    case GenServer.start_link(__MODULE__, status, name: get_name(key)) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        :ignore
    end
  end

  @spec get(key()) :: status()
  def get(key) do
    GenServer.call(get_name(key), :get)
  end

  @spec put(key(), status()) :: :ok
  def put(key, status) do
    GenServer.cast(get_name(key), {:put, status})
  end

  @spec stop(key()) :: :ok
  def stop(key) do
    GenServer.cast(get_name(key), :stop)
  end

  @impl GenServer
  def init(status) do
    {:ok, status}
  end

  @impl GenServer
  def handle_call(:get, _from, status) do
    {:reply, status, status}
  end

  @impl GenServer
  def handle_cast({:put, status}, _status) do
    {:noreply, status}
  end

  @impl GenServer
  def handle_cast(:stop, status) do
    {:stop, :normal, status}
  end

  defp get_name(key), do: :"#{__MODULE__}_#{key}"
end
