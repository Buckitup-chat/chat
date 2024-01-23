defmodule ChatWeb.MainLive.Page.Shared do
  @moduledoc "Shared page functions"

  alias Chat.Identity
  alias ChatWeb.OnlinersPresence
  alias Phoenix.HTML.Safe
  alias Phoenix.LiveView.Socket

  def mime_type(nil), do: "application/octet-stream"
  def mime_type(""), do: mime_type(nil)
  def mime_type(x), do: x

  def format_size(n) when n > 1_000_000_000, do: "#{trunc(n / 100_000_000) / 10} Gb"
  def format_size(n) when n > 1_000_000, do: "#{trunc(n / 100_000) / 10} Mb"
  def format_size(n) when n > 1_000, do: "#{trunc(n / 100) / 10} Kb"
  def format_size(n), do: "#{n} b"

  def is_memo?(text), do: String.length(text) > 150

  def render_to_html_string(assigns, render_fun) do
    assigns
    |> then(render_fun)
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  def track_onliners_presence(%Socket{} = socket) do
    OnlinersPresence.track(socket.root_pid, presence_key(socket), get_user_keys(socket))

    socket
  end

  def update_onliners_presence(%Socket{} = socket) do
    OnlinersPresence.update(socket.root_pid, presence_key(socket), get_user_keys(socket))

    socket
  end

  def untrack_onliners_presence(%Socket{} = socket) do
    OnlinersPresence.untrack(socket.root_pid, presence_key(socket))

    socket
  end

  defp presence_key(%Socket{assigns: %{me: me}}) do
    Enigma.hash(me)
  end

  defp get_user_keys(%Socket{assigns: %{me: me, room_map: room_map}})
       when not is_nil(me) and not is_nil(room_map) do
    room_map
    |> Stream.map(fn {_key, room} -> room end)
    |> Stream.concat([me])
    |> Enum.map(&Identity.pub_key/1)
    |> MapSet.new()
  end

  defp get_user_keys(_socket), do: MapSet.new()
end
