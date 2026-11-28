defmodule ChatWeb.MainLive.Page.Lobby.Users do
  @moduledoc """
  The lobby user list: all users with me first, or the users matching a search term.

  Part of the `ChatWeb.MainLive.Page.Lobby` namespace.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Chat.User.UsersBroker

  def assign_user_list(socket, search_term \\ "")

  def assign_user_list(%{assigns: %{my_id: id}} = socket, search_term) when search_term == "" do
    socket
    |> assign(
      :users,
      UsersBroker.list()
      |> Enum.split_with(fn card -> card.pub_key == id end)
      |> then(fn {[mine], others} -> [mine | others] end)
    )
  end

  def assign_user_list(%{assigns: %{my_id: id}} = socket, search_term) do
    socket
    |> assign(
      :users,
      UsersBroker.list(search_term) |> Enum.reject(fn user -> user.pub_key == id end)
    )
  end
end
