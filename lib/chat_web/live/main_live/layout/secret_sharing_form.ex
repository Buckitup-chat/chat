defmodule ChatWeb.MainLive.Layout.SecretSharingForm do
  @moduledoc """
  Handles showing and updating secret sharing as a setting
  """

  use ChatWeb, :live_component

  import Phoenix.Component

  alias Chat.User.Registry
  alias Chat.Card
  alias Chat.Dialogs.{DialogMessaging, Dialog}
  alias Chat.Messages.Text

  @impl Phoenix.LiveComponent
  def mount(socket) do
    users =
      Registry.all()
      |> Stream.map(fn {pub_key, %Card{} = user} -> {pub_key, user.name} end)
      |> Enum.to_list()
      |> Enum.sort_by(&elem(&1, 1))

    {:ok,
     socket
     |> assign(:secret_holders, [])
     |> assign(:user_options, users)
     |> assign(:selected_pb_key, nil)
     |> assign(:selected_kind, nil)
     |> assign(:threshold, 3)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("select_user", %{"pub-key" => pub_key, "kind" => kind}, socket)
      when kind in ["share-holders", "rest"] do
    {:noreply,
     socket
     |> assign(:selected_pb_key, decode_pub_key(pub_key))
     |> assign(:selected_kind, kind)}
  end

  def handle_event("add_holder", _params, socket) do
    {updated_options, updated_holders} =
      from_one_to_another(
        socket.assigns.user_options,
        socket.assigns.secret_holders,
        socket.assigns.selected_pb_key
      )

    {:noreply,
     socket
     |> assign(:secret_holders, updated_holders)
     |> assign(:user_options, updated_options)
     |> assign(:selected_kind, "share-holders")}
  end

  def handle_event("remove_holder", _params, socket) do
    {updated_holders, updated_options} =
      from_one_to_another(
        socket.assigns.secret_holders,
        socket.assigns.user_options,
        socket.assigns.selected_pb_key
      )

    {:noreply,
     socket
     |> assign(:secret_holders, updated_holders)
     |> assign(:user_options, updated_options)
     |> assign(:selected_kind, "rest")}
  end

  def handle_event("secret_share", _params, socket) do
    share_holders = socket.assigns.secret_holders
    secret_sharer = socket.assigns.me

    shares =
      secret_sharer.private_key
      |> Enigma.hide_secret_in_shares(length(share_holders), socket.assigns.threshold)

    for {{key, _name}, share} <- Enum.zip(share_holders, shares) do
      dialog = Dialog.start(secret_sharer, %Chat.Card{pub_key: key})

      Text.new(share |> Base.encode64(), DateTime.utc_now() |> DateTime.to_unix())
      |> DialogMessaging.add_new_message(secret_sharer, dialog)
    end

    {:noreply, socket}
  end

  defp from_one_to_another(list1, list2, pb_key) do
    element = Enum.find(list1, fn {key, _name} -> key == pb_key end)
    {list1 -- [element], [element | list2]}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <section class="flex flex-row mt-4">
      <.container
        myself={@myself}
        selected_pb_key={@selected_pb_key}
        title="Share Holders"
        kind="share-holders"
        users={@secret_holders}
      />

      <.buttons
        myself={@myself}
        selected_kind={@selected_kind}
        shares={@secret_holders}
        threshold={@threshold}
      />

      <.container
        myself={@myself}
        selected_pb_key={@selected_pb_key}
        title="Other Users"
        kind="rest"
        users={@user_options}
      />
    </section>
    """
  end

  def container(assigns) do
    ~H"""
    <div class="flex w-48 h-64 rounded-md">
      <div class="mx-1 flex w-full h-full flex-col border border-gray-300 rouznded-md bg-white">
        <div class="text-lg bg-gray-100 rounded-t-md p-2 users-title"><%= @title %></div>

        <.users_list myself={@myself} selected_pb_key={@selected_pb_key} kind={@kind} users={@users} />
      </div>
    </div>
    """
  end

  defp users_list(assigns) do
    ~H"""
    <ul
      class="h-full overflow-y-scroll overflow-x-hidden users-list"
      id={"users-" <> @kind}
      phx-target={@myself}
    >
      <%= for {pub_key, name} <- @users do %>
        <.user
          myself={@myself}
          selected_pb_key={@selected_pb_key}
          name={name}
          pub_key={pub_key}
          kind={@kind}
        />
      <% end %>
    </ul>
    """
  end

  defp user(assigns) do
    ~H"""
    <li
      class={"cursor-pointer" <> if(@selected_pb_key == @pub_key, do: " bg-gray-200 selected-user", else: "")}
      phx-click="select_user"
      phx-target={@myself}
      phx-value-kind={@kind}
      phx-value-pub-key={encode_pub_key(@pub_key)}
    >
      <div class="content">
        <div class="flex-1 px-2 py-2 truncate whitespace-normal">
          <p class="text-sm font-bold"><%= @name %></p>
        </div>
      </div>
    </li>
    """
  end

  defp encode_pub_key(pub_key), do: Base.encode16(pub_key, case: :lower)
  defp decode_pub_key(pub_key), do: Base.decode16!(pub_key, case: :lower)

  defp buttons(assigns) do
    ~H"""
    <div class="flex flex-col self-center mx-8 my-auto">
      <p class="w-32 text-sm">
        Share Holders are the users you will share your secret with after pressing the Send button.
      </p>

      <.button disabled={@selected_kind != "rest"} event="add_holder" myself={@myself} text="Add" />

      <.button
        disabled={@selected_kind != "share-holders"}
        event="remove_holder"
        myself={@myself}
        text="Remove"
      />

      <.button
        disabled={length(@shares) >= @threshold}
        event="secret_share"
        myself={@myself}
        text="Send Shares"
      />
    </div>
    """
  end

  defp button(assigns) do
    ~H"""
    <button
      class={"mx-auto mt-6 h-11 px-8 text-white border-0 rounded-lg bg-grayscale flex items-center justify-center" <> if(@disabled, do: " opacity-60", else: "")}
      disabled={@disabled}
      phx-click={@event}
      phx-target={@myself}
    >
      <%= @text %>
    </button>
    """
  end
end
