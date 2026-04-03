defmodule Chat.TimeKeeper do
  @moduledoc """
  Maintains accurate time on devices without a battery-backed RTC.

  On boot, tries NTP briefly, then falls back to a persisted time file,
  then to file mtime heuristics. Sets system clock ONCE at boot.

  After boot, tracks time as a monotonic offset. LiveView clients and
  shape writers call `update_time/1` to refine the offset without
  touching the system clock (avoiding Postgrex pool disruption).

  All non-Ecto code should use `now/0` or `now_unix/0` instead of
  `DateTime.utc_now()`.
  """

  use GenServer

  use Toolbox.OriginLog

  @persist_interval :timer.minutes(3)
  @ntp_timeout 3_000
  @ntp_servers ["pool.ntp.org", "time.google.com", "time.cloudflare.com"]
  @ntp_epoch_offset 2_208_988_800

  @pt_key {__MODULE__, :offset}

  # --- Public API (lock-free reads via :persistent_term) ---

  @doc "Current time as DateTime. Replaces `DateTime.utc_now()`."
  def now do
    now_unix()
    |> DateTime.from_unix!()
  end

  @doc "Current time as unix seconds."
  def now_unix do
    case :persistent_term.get(@pt_key, nil) do
      nil -> DateTime.utc_now() |> DateTime.to_unix()
      offset -> System.monotonic_time(:second) + offset
    end
  end

  @doc "Current global monotonic offset."
  def monotonic_offset do
    :persistent_term.get(@pt_key, nil) ||
      monotonic_offset(DateTime.utc_now() |> DateTime.to_unix())
  end

  @doc "Accept a time update from a client. Updates offset only if newer."
  def update_time(unix_timestamp) when is_integer(unix_timestamp) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, {:update_time, unix_timestamp})
    end
  end

  # --- Static functions (callable before GenServer starts) ---

  @doc "Try to get time from NTP servers. Returns `{:ok, unix}` or `:error`."
  def try_ntp(timeout \\ @ntp_timeout) do
    Enum.find_value(@ntp_servers, :error, fn server ->
      case ntp_query(server, timeout) do
        {:ok, unix} -> {:ok, unix}
        :error -> nil
      end
    end)
  end

  @doc "Read persisted unix timestamp from file."
  def read_persisted_time(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.trim()
        |> String.to_integer()
        |> DateTime.from_unix!()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  def persist_path do
    Application.get_env(:chat, :timekeeper_path, "priv/timekeeper_time")
  end

  # --- GenServer ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    path = persist_path()

    offset =
      DateTime.utc_now()
      |> DateTime.to_unix()
      |> monotonic_offset()

    :persistent_term.put(@pt_key, offset)

    timer = Process.send_after(self(), :persist, @persist_interval)

    log("started, offset=#{offset}", :info)

    {:ok, %{offset: offset, persist_path: path, persist_timer: timer}}
  end

  @impl true
  def handle_cast({:update_time, unix_timestamp}, state) do
    current_unix = System.monotonic_time(:second) + state.offset

    if unix_timestamp > current_unix do
      new_offset = monotonic_offset(unix_timestamp)
      :persistent_term.put(@pt_key, new_offset)

      log(["offset updated, delta=", Integer.to_string(unix_timestamp - current_unix), "s"], :debug)

      {:noreply, %{state | offset: new_offset}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:persist, state) do
    unix = System.monotonic_time(:second) + state.offset

    case File.write(state.persist_path, Integer.to_string(unix)) do
      :ok -> :ok
      {:error, reason} -> log("persist failed: #{inspect(reason)}", :warning)
    end

    timer = Process.send_after(self(), :persist, @persist_interval)
    {:noreply, %{state | persist_timer: timer}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp monotonic_offset(unix_timestamp) do
    unix_timestamp - System.monotonic_time(:second)
  end

  # --- NTP ---

  defp ntp_query(server, timeout) do
    with {:ok, addr} <- resolve_host(server, timeout),
         {:ok, socket} <- :gen_udp.open(0, [:binary, active: false]),
         :ok <- :gen_udp.send(socket, addr, 123, ntp_request_packet()),
         {:ok, {_, _, response}} <- :gen_udp.recv(socket, 0, timeout) do
      :gen_udp.close(socket)
      parse_ntp_response(response)
    else
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp resolve_host(server, timeout) do
    case :inet.getaddr(~c"#{server}", :inet, timeout) do
      {:ok, addr} -> {:ok, addr}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp ntp_request_packet do
    # LI=0, VN=3, Mode=3 (client)
    <<0x1B>> <> :binary.copy(<<0>>, 47)
  end

  defp parse_ntp_response(<<_::binary-size(40), seconds::32, _fraction::32, _::binary>>)
       when seconds > @ntp_epoch_offset do
    {:ok, seconds - @ntp_epoch_offset}
  end

  defp parse_ntp_response(_), do: :error
end
