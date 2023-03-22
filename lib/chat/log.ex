defmodule Chat.Log do
  @moduledoc "All acrions log"

  alias Chat.Card
  alias Chat.Identity
  alias Chat.Rooms.Room

  alias Chat.Db
  alias Chat.Ordering

  @db_key :action_log

  def sign_in(me, time), do: me |> log(time, :sign_in)
  def visit(me, time), do: me |> log(time, :visit)
  def export_keys(me, time), do: me |> log(time, :export_keys)
  def self_backup(me, time), do: me |> log(time, :self_backup)
  def logout(me, time), do: me |> log(time, :logout)

  def create_room(me, time, room, type),
    do: me |> log(time, :create_room, room: pub_key(room), room_type: type)

  def message_room(me, time, room), do: me |> log(time, :message_room, room: pub_key(room))

  def delete_room_message(me, time, room),
    do: me |> log(time, :delete_room_message, room: pub_key(room))

  def update_room_message(me, time, room),
    do: me |> log(time, :update_room_message, room: pub_key(room))

  def request_room_key(me, time, room),
    do: me |> log(time, :request_room_key, room: pub_key(room))

  def got_room_key(me, time, room), do: me |> log(time, :got_room_key, room: pub_key(room))
  def visit_room(me, time, room), do: me |> log(time, :visit_room, room: pub_key(room))

  def approve_room_request(me, time, room),
    do: me |> log(time, :approve_room_request, room: pub_key(room))

  def open_direct(me, time, peer), do: me |> log(time, :open_direct, to: pub_key(peer))
  def message_direct(me, time, peer), do: me |> log(time, :message_direct, to: pub_key(peer))

  def delete_message_direct(me, time, peer),
    do: me |> log(time, :delete_message_direct, to: pub_key(peer))

  def update_message_direct(me, time, peer),
    do: me |> log(time, :update_message_direct, to: pub_key(peer))

  @human_actions %{
    open_direct: "reads dialog",
    message_direct: "writes message",
    delete_message_direct: "removes message",
    update_message_direct: "edits message",
    sign_in: "signs in",
    visit: "visits",
    export_keys: "exports keys",
    self_backup: "downloads own keys",
    logout: "signs out",
    create_room: "creates room",
    message_room: "writes in room",
    update_room_message: "edits in room",
    delete_room_message: "deletes in room",
    request_room_key: "requests key of room",
    approve_room_request: "approves request for room",
    got_room_key: "got key for room",
    visit_room: "reads room"
  }

  def humanize_action(action), do: Map.get(@human_actions, action, "unknown act")

  def list do
    list(Ordering.last({@db_key}) + 1)
  end

  def list(since) do
    list(since, max(since - 100, 0))
  end

  def list(later, earlier) do
    {build(later, earlier), earlier}
  end

  @spec build(integer, integer) :: [{time :: integer, who :: String.t(), what :: any()}, ...]
  defp build(later, earlier) do
    {{@db_key, earlier, ""}, {@db_key, later, :binary.copy(<<255>>, 100)}}
    |> Db.list()
    |> Enum.map(fn {{@db_key, _index, who}, data} -> {who, data} end)
    |> Enum.reverse()
  end

  defp log(me, time, action) do
    {@db_key, Ordering.next({@db_key}), pub_key(me)}
    |> Db.put({time, action})
  end

  defp log(me, time, action, opts) do
    {@db_key, Ordering.next({@db_key}), pub_key(me)}
    |> Db.put({time, action, opts})
  end

  defp pub_key(%Identity{public_key: key}), do: key
  defp pub_key(%Card{pub_key: key}), do: key
  defp pub_key(%Room{pub_key: key}), do: key
  defp pub_key(x), do: x
end
