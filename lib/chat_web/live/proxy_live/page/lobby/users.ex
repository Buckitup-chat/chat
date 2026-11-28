defmodule ChatWeb.ProxyLive.Page.Lobby.Users do
  @moduledoc """
  Proxy lobby user list: fetching users from the proxied server, caching them in the socket
  and assigning the (optionally filtered) list.

  Used by `ChatWeb.ProxyLive.Page.Lobby`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Tools.SocketPrivate

  alias ChatWeb.State.ActorState

  def assign_user_list(socket, search_term \\ "") do
    cache = socket |> get_private(:users_cache, [])

    user_list =
      case search_term do
        "" -> me_first_and_user_list(cache, ActorState.my_pub_key(socket))
        search_term -> matching_user_list(cache, search_term)
      end

    socket
    |> assign(:users, user_list)
  end

  def make_user_list_request(socket) do
    server = socket |> get_private(:server)

    request_user_list(server, ActorState.my_identity(socket))
  end

  def populate_user_list(socket, user_list) do
    socket
    |> set_private(:users_cache, user_list)
    |> assign_user_list()
  end

  def append_user(socket, user) do
    users_cache = socket |> get_private(:users_cache)

    socket
    |> set_private(:users_cache, [user | users_cache] |> Enum.uniq())
    |> assign_user_list()
  end

  defp me_first_and_user_list(cache, my_pubkey) do
    cache
    |> Enum.split_with(fn card -> card.pub_key == my_pubkey end)
    |> then(fn
      {[mine], others} -> [mine | others]
      {[], others} -> others
    end)
  end

  defp matching_user_list(cache, search_term) do
    cache
    |> Enum.filter(fn card -> String.contains?(card.name, search_term) end)
  end

  defp request_user_list(server, me) do
    pid = self()

    Task.start(fn ->
      Proxy.register_me(server, me)
      users = Proxy.get_users(server)

      if is_list(users) do
        send(pid, {:lobby, {:user_list, users}})
      end
    end)
  end
end
