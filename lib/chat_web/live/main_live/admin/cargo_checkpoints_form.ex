defmodule ChatWeb.MainLive.Admin.CargoCheckpointsForm do
  @moduledoc """
  Handles showing and updating cargo checkpoints form data.
  """

  use ChatWeb, :live_component

  import Phoenix.Component

  alias Chat.Admin.CargoSettings
  alias Chat.AdminRoom
  alias Chat.User.UsersBroker

  alias ChatWeb.MainLive.Layout

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket
    |> assign(:cargo_settings, AdminRoom.get_cargo_settings())
    |> assign_checkpoints()
    |> reset_selected_user()
    |> ok()
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> handle_update(assigns)
    |> ok()
  end

  defp handle_update(socket, %{action: :refresh}),
    do: socket |> assign_checkpoints() |> reset_selected_user()

  defp handle_update(socket, _assigns), do: socket

  defp assign_checkpoints(%{assigns: %{cargo_settings: %{checkpoints: checkpoints}}} = socket) do
    socket
    |> assign(:checkpoints, checkpoints)
    |> assign(:rest, UsersBroker.list() |> Enum.reject(fn card -> card in checkpoints end))
  end

  defp reset_selected_user(socket) do
    socket
    |> assign(:selected_card, nil)
    |> assign(:selected_type, nil)
  end

  @impl Phoenix.LiveComponent
  def handle_event("add_checkpoint", _params, %{assigns: %{selected_card: card}} = socket) do
    socket
    |> add_checkpoint(card)
    |> noreply()
  end

  def handle_event("remove_checkpoint", _params, %{assigns: %{selected_card: card}} = socket) do
    socket
    |> remove_checkpoint(card)
    |> noreply()
  end

  def handle_event("move_user", %{"pub_key" => pub_key, "type" => "rest"}, socket) do
    socket
    |> add_checkpoint(get_user_card(socket.assigns.rest, pub_key))
    |> noreply()
  end

  def handle_event("move_user", %{"pub_key" => pub_key, "type" => "checkpoints"}, socket) do
    socket
    |> remove_checkpoint(get_user_card(socket.assigns.checkpoints, pub_key))
    |> noreply()
  end

  def handle_event("select_user", %{"pub-key" => pub_key, "type" => "checkpoints"}, socket) do
    socket
    |> select_user_card(socket.assigns.checkpoints, pub_key, "checkpoints")
    |> noreply()
  end

  def handle_event("select_user", %{"pub-key" => pub_key, "type" => "rest"}, socket) do
    socket
    |> select_user_card(socket.assigns.rest, pub_key, "rest")
    |> noreply()
  end

  defp select_user_card(socket, cards, pub_key, type) do
    socket
    |> assign(:selected_card, get_user_card(cards, pub_key))
    |> assign(:selected_type, type)
  end

  defp get_user_card(cards, pub_key),
    do: Enum.find(cards, &(&1.pub_key == decode_pub_key(pub_key)))

  defp add_checkpoint(%{assigns: %{checkpoints: checkpoints, rest: rest}} = socket, card) do
    new_checkpoints = checkpoints ++ [card]
    next_card = get_next_card(rest, card)

    update_checkpoints(socket, new_checkpoints, next_card)
  end

  defp remove_checkpoint(%{assigns: %{checkpoints: checkpoints}} = socket, card) do
    new_checkpoints = checkpoints -- [card]
    next_card = get_next_card(checkpoints, card)

    update_checkpoints(socket, new_checkpoints, next_card)
  end

  defp get_next_card(cards, card) do
    index = Enum.find_index(cards, fn c -> c == card end)
    cards_count = length(cards)

    next_index =
      cond do
        index + 1 < cards_count ->
          index + 1

        cards_count > 1 ->
          index - 1

        true ->
          nil
      end

    if next_index, do: Enum.at(cards, next_index)
  end

  defp update_checkpoints(socket, checkpoints, next_card) do
    changeset =
      socket.assigns.cargo_settings
      |> CargoSettings.checkpoints_changeset(%{checkpoints: checkpoints})
      |> Map.put(:action, :validate)

    if changeset.valid? do
      cargo_settings = Ecto.Changeset.apply_changes(changeset)
      :ok = AdminRoom.store_cargo_settings(cargo_settings)

      send(self(), :update_cargo_settings)

      socket
      |> assign(:cargo_settings, cargo_settings)
      |> assign_checkpoints()
      |> maybe_select_next_user(next_card)
    else
      reset_selected_user(socket)
    end
  end

  defp maybe_select_next_user(socket, nil), do: reset_selected_user(socket)

  defp maybe_select_next_user(socket, next_card),
    do: assign(socket, :selected_card, next_card)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <section class="flex flex-col md:flex-row mt-4">
      <.container
        myself={@myself}
        selected_card={@selected_card}
        title="Checkpoints"
        type="checkpoints"
        users={@checkpoints}
      />

      <.buttons myself={@myself} selected_type={@selected_type} />

      <.container
        myself={@myself}
        selected_card={@selected_card}
        title="Other users"
        type="rest"
        users={@rest}
      />
    </section>
    """
  end

  def container(assigns) do
    ~H"""
    <div class="flex w-48 h-64 rounded-md">
      <div class="mx-1 flex w-full h-full flex-col border border-gray-300 rounded-md bg-white">
        <div class="text-lg bg-gray-100 rounded-t-md p-2 users-title">{@title}</div>

        <.users_list myself={@myself} selected_card={@selected_card} type={@type} users={@users} />
      </div>
    </div>
    """
  end

  defp users_list(assigns) do
    ~H"""
    <ul
      class="h-full overflow-y-scroll overflow-x-hidden users-list"
      id={"users-" <> @type}
      phx-target={@myself}
    >
      <%= for user <- @users do %>
        <.user myself={@myself} selected_card={@selected_card} card={user} type={@type} />
      <% end %>
    </ul>
    """
  end

  defp user(assigns) do
    ~H"""
    <li
      class={"cursor-pointer" <> if(@selected_card == @card, do: " bg-gray-200 selected-user", else: "")}
      phx-click="select_user"
      phx-target={@myself}
      phx-value-type={@type}
      phx-value-pub-key={encode_pub_key(@card.pub_key)}
    >
      <div class="content">
        <div class="flex-1 px-2 py-2 truncate whitespace-normal">
          <Layout.Card.hashed_name card={@card} />
        </div>
      </div>
    </li>
    """
  end

  defp encode_pub_key(pub_key), do: Base.encode16(pub_key, case: :lower)
  defp decode_pub_key(pub_key), do: Base.decode16!(pub_key, case: :lower)

  defp buttons(assigns) do
    ~H"""
    <div class="t-buttons flex flex-col self-center md:mx-8 mr-[5rem] my-5 md:my-auto">
      <p class="w-32 text-sm">Checkpoints are automatically invited to the Cargo rooms you create.</p>

      <.button disabled={@selected_type != "rest"} event="add_checkpoint" myself={@myself} text="Add" />

      <.button
        disabled={@selected_type != "checkpoints"}
        event="remove_checkpoint"
        myself={@myself}
        text="Remove"
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
      {@text}
    </button>
    """
  end
end
