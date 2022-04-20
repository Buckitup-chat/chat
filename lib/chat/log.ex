defmodule Chat.Log do
  @moduledoc "All acrions log"

  import Chat.Utils, only: [binhash: 1, hash: 1]

  alias Chat.Db

  @db_key :action_log

  def sign_in(me), do: me |> log(:sign_in)
  def visit(me), do: me |> log(:visit)
  def export_keys(me), do: me |> log(:export_keys)
  def self_backup(me), do: me |> log(:self_backup)
  def logout(me), do: me |> log(:logout)

  def create_room(me, room), do: me |> log(:create_room, room: binhash(room))
  def message_room(me, room), do: me |> log(:message_room, room: binhash(room))
  def request_room_key(me, room), do: me |> log(:request_room_key, room: binhash(room))
  def got_room_key(me, room), do: me |> log(:got_room_key, room: binhash(room))
  def visit_room(me, room), do: me |> log(:visit_room, room: binhash(room))

  def open_direct(me, peer), do: me |> log(:open_direct, to: binhash(peer))
  def message_direct(me, peer), do: me |> log(:message_direct, to: binhash(peer))

  @human_actions %{
    open_direct: "reads dialog",
    message_direct: "writes message",
    sign_in: "signs in",
    visit: "visits",
    export_keys: "exports keys",
    self_backup: "downloads own keys",
    logout: "signs out",
    create_room: "creates room",
    message_room: "writes in room",
    request_room_key: "requests key of room",
    got_room_key: "got key for room",
    visit_room: "reads room"
  }

  def humanize_action(action), do: Map.get(@human_actions, action, "unknown act")

  def list do
    list(time() + 1)
  end

  def list(since) do
    list(since, since - (time() - since) - 3600)
  end

  def list(later, earlier) do
    {build(later, earlier), earlier}
  end

  def start_time, do: 1_585_574_426

  @spec build(integer, integer) :: [{time :: integer, who :: String.t(), what :: any()}, ...]
  defp build(later, earlier) do
    {{@db_key, earlier, ""}, {@db_key, later, :binary.copy(<<255>>, 100)}}
    |> Db.list()
    |> Enum.map(fn {{@db_key, time, who}, action} -> {time, hash(who), action} end)
    |> Enum.reverse()
  end

  defp log(me, action) do
    {@db_key, time(), binhash(me)}
    |> Db.put(action)
  end

  defp log(me, action, opts) do
    {@db_key, time(), binhash(me)}
    |> Db.put({action, opts})
  end

  defp time, do: System.system_time(:second)
end
