defmodule ChatWeb.MainLive.Page.ImportOwnKeyRing do
  @moduledoc "Import Own Key Ring  from uploaded file"
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [consume_uploaded_entries: 3]

  alias Chat.Actor

  alias ChatWeb.MainLive.Page

  def init(socket) do
    socket
    |> assign(:mode, :import_own_key_ring)
    |> assign(:step, :initial)
  end

  def read_file(socket) do
    {encrypted, filename} =
      consume_uploaded_entries(
        socket,
        :my_keys_file,
        fn %{path: path}, entry ->
          data = File.read!(path)
          {:ok, {data, entry.client_name}}
        end
      )
      |> Enum.at(0)

    case check_password(encrypted, "") do
      {:ok, %{me: me, rooms: rooms}} ->
        socket
        |> close()
        |> Page.Login.load_user(me, rooms)
        |> Page.Login.store()
        |> Page.Lobby.init()
        |> Page.Dialog.init()
        |> Page.Logout.init()
        |> Page.Shared.track_onliners_presence()

      _ ->
        socket
        |> assign(:encrypted, encrypted)
        |> assign(:step, :decrypt)
        |> assign(:filename, filename)
        |> assign(:show_invalid, false)
    end
  end

  def try_password(%{assigns: %{encrypted: encrypted}} = socket, password) do
    case check_password(encrypted, password) do
      {:ok, %{me: me, rooms: rooms}} ->
        socket
        |> close()
        |> Page.Login.load_user(me, rooms)
        |> Page.Login.store()
        |> Page.Lobby.init()
        |> Page.Dialog.init()
        |> Page.Logout.init()
        |> Page.Shared.track_onliners_presence()

      _ ->
        socket
        |> assign(:show_invalid, true)
    end
  end

  def back_to_file(socket) do
    socket
    |> close()
    |> assign(:step, :initial)
  end

  def drop_error(socket) do
    socket
    |> assign(:show_invalid, false)
  end

  def close(socket) do
    socket
    |> assign(:step, nil)
    |> assign(:encrypted, nil)
    |> assign(:filename, nil)
    |> assign(:show_invalid, nil)
  end

  defp check_password(data, password) do
    data
    |> Actor.from_encrypted_json(password)
    |> then(&{:ok, &1})
  rescue
    _ -> {:error, :wrong_password}
  end
end
