defmodule Chat.NetworkSynchronization.PeerDetection.LanDetector do
  @moduledoc "Detects LAN peers"
  use GenServer
  import Tools.GenServerHelpers

  alias Chat.NetworkSynchronization.PeerDetection.LanDetection

  @startup_delay :timer.minutes(1)
  @refresh_delay :timer.minutes(30)
  @restart_delay :timer.minutes(70)

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    start_timers() |> ok
  end

  ########### Messaging ################

  @impl true
  def handle_info(:update, restart_timer) do
    request_lan_range()
    restart_timer |> noreply
  end

  def handle_info(:restart, _restart_timer) do
    send(self(), :update)
    reset_timers() |> noreply()
  end

  def handle_info({:range, range}, restart_timer) do
    cancel_timer(restart_timer)
    on_lan_range(range)
    reset_timers() |> noreply()
  end

  ########### Logic ################

  def request_lan_range do
    topic = Application.get_env(:chat, :topic_to_platform)
    Phoenix.PubSub.broadcast(Chat.PubSub, topic, {:lan_ip_and_mask, self()})
  end

  def on_lan_range({ip, mask}) do
    LanDetection.on_lan(ip, mask)
  end

  ########### Timers ################

  defp start_timers do
    Process.send_after(self(), :update, @startup_delay)
    Process.send_after(self(), :restart, @restart_delay)
  end

  defp reset_timers do
    Process.send_after(self(), :update, @refresh_delay)
    Process.send_after(self(), :restart, @restart_delay)
  end

  # coveralls-ignore-next-line
  defp cancel_timer(nil), do: nil
  defp cancel_timer(timer), do: Process.cancel_timer(timer)
end
