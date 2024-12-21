defmodule ChatWeb.MainLive.Page.RoomForm do
  @moduledoc """
  Handles showing and updating room form data.
  """

  use ChatWeb, :live_component

  alias Chat.Rooms.RoomInput
  alias Chat.Sync.{CargoRoom, UsbDriveDumpRoom}

  @types_map %{
    public: "Public room is visible for everyone. Anyone can join.",
    request:
      "Private Room is visible for everyone. Anyone can send request and join if approved by a room member",
    private: "Secret Room is not visible, only invited users can join",
    cargo: "Cargo room is special"
  }

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_changeset()}
  end

  defp assign_changeset(socket) do
    params =
      case socket.assigns[:changeset] do
        nil ->
          %{}

        %Ecto.Changeset{} = changeset ->
          changeset.params
      end

    changeset = RoomInput.changeset(%RoomInput{}, params, socket.assigns.media_settings)
    assign(socket, :changeset, changeset)
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate", %{"room_input" => params}, socket) do
    changeset =
      %RoomInput{}
      |> RoomInput.changeset(params, socket.assigns.media_settings)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"room_input" => params}, socket) do
    changeset =
      %RoomInput{}
      |> RoomInput.changeset(params, socket.assigns.media_settings)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      %RoomInput{} = input = Ecto.Changeset.apply_changes(changeset)
      send(self(), {:create_new_room, %{name: input.name, type: input.type}})

      {:noreply,
       socket
       |> reset_changeset()
       |> push_event("js-exec", %{to: "#room-create-form", attr: "data-success"})}
    else
      {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp reset_changeset(socket) do
    socket
    |> assign(:changeset, nil)
    |> assign_changeset()
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign_new(assigns, :types_map, fn -> @types_map end)

    ~H"""
    <div>
      <.form
        :let={f}
        for={@changeset}
        id="room-create-form"
        autocomplete="off"
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
        data-success={hide_modal("create-room-popup")}
      >
        {text_input(f, :name,
          placeholder: "Name your Room",
          class: "w-full h-11 mt-4 border border-gray-300 rounded-lg focus:outline-none focus:ring-0"
        )}

        <.error_message form={f} field={:name} />

        <p class="mt-3 text-black/50 text-sm">Room Type</p>

        <div class="mt-3 flex flex-col">
          <.type_radio_button
            checked={true}
            class="t-open-room"
            form={f}
            id="typeChoice1"
            name="Open"
            value={:public}
          />
          <.type_radio_button form={f} id="typeChoice2" name="Private" value={:request} />
          <.type_radio_button
            class="t-secret-room"
            form={f}
            id="typeChoice3"
            name="Secret"
            value={:private}
          />
          <%= if @media_settings.functionality == :cargo and !match?(%CargoRoom{status: :syncing}, @cargo_room) and !match?(%UsbDriveDumpRoom{status: :dumping}, @usb_drive_dump_room) do %>
            <.type_radio_button form={f} id="typeChoice4" name="Cargo" value={:cargo} />
          <% end %>
        </div>

        <.error_message form={f} field={:type} />

        <div class="mt-5 py-1 w-full min-h-fit flex items-center justify-start border-0 rounded-lg bg-black/10">
          <.icon id="alert" class="basis-1/12 mr-2 w-4 h-4 fill-black/40" />
          <blockquote id="roomTypeDescription" class="basis-11/12 text-xs text-black/50 mr-3">
            {Map.get(@types_map, selected_type(f))}
          </blockquote>
        </div>

        {submit("Create",
          disabled: !@changeset.valid?,
          phx_disable_with: "Saving...",
          class:
            "w-full h-11 mt-2 text-white border-0 rounded-lg bg-grayscale flex items-center justify-center t-submit-create"
        )}
      </.form>
    </div>
    """
  end

  defp error_message(assigns) do
    ~H"""
    <div class="my-2">
      {error_tag(@form, @field)}
    </div>
    """
  end

  defp type_radio_button(assigns) do
    assigns =
      assigns
      |> assign_new(:class, fn -> "" end)

    ~H"""
    <a class={"flex items-center" <> if(@class, do: " #{@class}", else: "")}>
      <%= label class: "cursor-pointer" do %>
        {radio_button(@form, :type, @value,
          class:
            "text-orange-500" <> if(selected_type?(@form, @value), do: " checkedBackground", else: ""),
          id: @id
        )}

        <span class={"ml-1 text-black/50 text-sm" <>if(selected_type?(@form, @value), do:  " font-bold", else: "")}>
          {@name}
        </span>
      <% end %>
    </a>
    """
  end

  defp selected_type?(form, value) do
    selected_type(form) == value
  end

  defp selected_type(form) do
    form
    |> input_value(:type)
    |> maybe_convert_to_atom()
  end

  defp maybe_convert_to_atom(value) when is_binary(value), do: String.to_existing_atom(value)
  defp maybe_convert_to_atom(value), do: value
end
