defmodule ChatWeb.MainLive.Admin.CargoCheckpointsForm do
  @moduledoc """
  Handles showing and updating cargo checkpoints form data.
  """

  use ChatWeb, :live_component

  import Phoenix.Component

  alias Chat.Admin.CargoSettings
  alias Chat.{AdminRoom, Card}
  alias Chat.User.Registry

  @impl Phoenix.LiveComponent
  def mount(socket) do
    cargo_settings = AdminRoom.get_cargo_settings()

    users =
      Registry.all()
      |> Stream.map(fn {pub_key, %Card{} = user} -> {pub_key, user.name} end)
      |> Enum.to_list()
      |> Enum.sort_by(&elem(&1, 1))

    {:ok,
     socket
     |> assign(:cargo_settings, cargo_settings)
     |> assign(:users, users)
     |> assign_checkpoints()
     |> reset_selected_user()}
  end

  defp assign_checkpoints(socket) do
    checkpoints_pub_keys = socket.assigns.cargo_settings.checkpoints

    {checkpoints, rest} =
      Enum.split_with(socket.assigns.users, fn {pub_key, _name} ->
        pub_key in checkpoints_pub_keys
      end)

    socket
    |> assign(:checkpoints, checkpoints)
    |> assign(:rest, rest)
  end

  defp reset_selected_user(socket) do
    socket
    |> assign(:selected_pub_key, nil)
    |> assign(:selected_type, nil)
  end

  @impl Phoenix.LiveComponent
  def handle_event("add_checkpoint", _params, socket) do
    pub_key = socket.assigns.selected_pub_key

    {:noreply, add_checkpoint(socket, pub_key)}
  end

  def handle_event("remove_checkpoint", _params, socket) do
    pub_key = socket.assigns.selected_pub_key

    {:noreply, remove_checkpoint(socket, pub_key)}
  end

  def handle_event("move_user", %{"pub_key" => pub_key, "type" => "rest"}, socket) do
    {:noreply, add_checkpoint(socket, decode_pub_key(pub_key))}
  end

  def handle_event("move_user", %{"pub_key" => pub_key, "type" => "checkpoints"}, socket) do
    {:noreply, remove_checkpoint(socket, decode_pub_key(pub_key))}
  end

  def handle_event("select_user", %{"pub-key" => pub_key, "type" => type}, socket)
      when type in ["checkpoints", "rest"] do
    {:noreply,
     socket
     |> assign(:selected_pub_key, decode_pub_key(pub_key))
     |> assign(:selected_type, type)}
  end

  defp add_checkpoint(socket, pub_key) do
    new_checkpoints = socket.assigns.cargo_settings.checkpoints ++ [pub_key]
    next_pub_key = get_next_pub_key(socket.assigns.rest, pub_key)
    update_checkpoints(socket, new_checkpoints, next_pub_key)
  end

  defp remove_checkpoint(socket, pub_key) do
    new_checkpoints = socket.assigns.cargo_settings.checkpoints -- [pub_key]
    next_pub_key = get_next_pub_key(socket.assigns.checkpoints, pub_key)
    update_checkpoints(socket, new_checkpoints, next_pub_key)
  end

  defp get_next_pub_key(users, pub_key) do
    index = Enum.find_index(users, fn {other_pub_key, _name} -> other_pub_key == pub_key end)
    users_count = length(users)

    next_index =
      cond do
        index + 1 < users_count ->
          index + 1

        users_count > 1 ->
          index - 1

        true ->
          nil
      end

    if next_index do
      users
      |> Enum.at(next_index)
      |> elem(0)
    end
  end

  defp update_checkpoints(socket, checkpoints, next_pub_key) do
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
      |> maybe_select_next_user(next_pub_key)
    else
      reset_selected_user(socket)
    end
  end

  defp maybe_select_next_user(socket, nil), do: reset_selected_user(socket)

  defp maybe_select_next_user(socket, next_pub_key),
    do: assign(socket, :selected_pub_key, next_pub_key)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <section class="flex flex-col md:flex-row mt-4">
      <.container
        myself={@myself}
        selected_pub_key={@selected_pub_key}
        title="Checkpoints"
        type="checkpoints"
        users={@checkpoints}
      />

      <.buttons myself={@myself} selected_type={@selected_type} />

      <.container
        myself={@myself}
        selected_pub_key={@selected_pub_key}
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
        <div class="text-lg bg-gray-100 rounded-t-md p-2 users-title"><%= @title %></div>

        <.users_list
          myself={@myself}
          selected_pub_key={@selected_pub_key}
          type={@type}
          users={@users}
        />
      </div>
    </div>
    """
  end

  defp users_list(assigns) do
    ~H"""
    <ul
      class="h-full overflow-y-scroll overflow-x-hidden users-list"
      id={"users-" <> @type}
      phx-hook="DraggableCheckpoints"
      phx-target={@myself}
    >
      <%= for {pub_key, name} <- @users do %>
        <.user
          myself={@myself}
          selected_pub_key={@selected_pub_key}
          name={name}
          pub_key={pub_key}
          type={@type}
        />
      <% end %>
    </ul>
    """
  end

  defp user(assigns) do
    ~H"""
    <li
      class={"cursor-pointer" <> if(@selected_pub_key == @pub_key, do: " bg-gray-200 selected-user", else: "")}
      phx-click="select_user"
      phx-target={@myself}
      phx-value-type={@type}
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
      <%= @text %>
    </button>
    """
  end
end
