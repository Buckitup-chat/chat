defmodule ChatWeb.MainLive.Modals.RoomInviteList do
  @moduledoc "Users to invite to room"
  use ChatWeb, :live_component

  alias ChatWeb.MainLive.Layout

  def render(assigns) do
    ~H"""
    <div id="room-invite-list">
      <h1 class="text-base font-bold text-grayscale t-invite-header">
        Invite to the Room
      </h1>
      <div id="user-list" class="mt-3 w-full flex flex-col">
        <%= for user <- @users do %>
          <div id={"user-#{user.hash}"} class="flex flex-row items-center justify-between t-invite">
            <Layout.Card.hashed_name card={user} />
            <a
              class="flex items-center justify-between"
              phx-click="invite"
              phx-value-hash={user.hash}
              phx-target={@myself}
            >
              <p class="text-purple font-semibold">Send invite</p>
              <.icon id="send" class="w-4 h-4 ml-2 z-20 fill-purple" />
            </a>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("invite", %{"hash" => hash}, %{assigns: %{users: users}} = socket) do
    send(self(), {:room, {:invite_user, hash}})

    users
    |> Enum.reject(fn user -> user.hash == hash end)
    |> case do
      [] ->
        socket
        |> close_modal()
        |> noreply()

      other_users ->
        socket
        |> assign(:users, other_users)
        |> noreply()
    end
  end
end
