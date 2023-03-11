defmodule ChatWeb.MainLive.Page.OnlinersPresence do
  alias Chat.Identity
  alias ChatWeb.Presence
  alias Phoenix.LiveView.Socket

  @topic "onliners_sync"

  def track(%Socket{} = socket) do
    {:ok, _} =
      Presence.track(socket.root_pid, @topic, presence_key(socket), %{
        keys: get_user_keys(socket)
      })

    socket
  end

  def update(%Socket{} = socket) do
    Presence.update(socket.root_pid, @topic, presence_key(socket), %{
      keys: get_user_keys(socket)
    })

    socket
  end

  def untrack(%Socket{} = socket) do
    Presence.untrack(socket.root_pid, @topic, presence_key(socket))

    socket
  end

  defp presence_key(%Socket{assigns: %{me: me}}) do
    Enigma.hash(me)
  end

  defp get_user_keys(%Socket{assigns: %{me: me, rooms: rooms}})
       when not is_nil(me) and not is_nil(rooms) do
    [me | rooms]
    |> Enum.map(&Identity.pub_key/1)
    |> MapSet.new()
  end

  defp get_user_keys(_socket), do: MapSet.new()
end
