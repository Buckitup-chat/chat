defmodule ChatWeb.MainLive.Admin.CargoUserData do
  @moduledoc "Cargo user info/form"
  use ChatWeb, :live_component

  alias Chat.Actor
  alias Chat.Broker
  alias Chat.Card
  alias Chat.User
  alias ChatWeb.MainLive.Layout

  @upload_options [
    accept: ~w(.data),
    max_entries: 1,
    max_file_size: 1_024_000_000,
    auto_upload: true,
    progress: &__MODULE__.handle_progress/3
  ]

  def update(%{cargo_user: nil} = assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(:valid_input?, false)
    |> assign(:invalid_upload?, false)
    |> allow_upload(:config, @upload_options)
    |> ok()
  end

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div>
      <%= if @cargo_user do %>
        <div class="mt-3">
          <Layout.Card.hashed_name card={Card.from_identity(@cargo_user)} />
          <button
            class="mt-3 px-10 w-full h-12 border-0 rounded-lg bg-grayscale flex items-center justify-center"
            phx-click="backup-keys"
            phx-target={@myself}
          >
            <div class="flex items-center justify-between">
              <span class="text-sm text-white t-download-key">Download the Keys</span>
              <.icon id="upload" class="w-4 h-4 ml-2 fill-white" />
            </div>
          </button>
        </div>
      <% else %>
        <div class="mt-3 w-80">Create a cargo user to have access to cargo settings.</div>
        <div class="mt-3">
          <.form
            :let={f}
            for={%{}}
            as={:user}
            id="cargo_user_form"
            phx-submit="create"
            phx-target={@myself}
            phx-change="validate"
          >
            <%= text_input(f, :name,
              placeholder: "Your name",
              class:
                "w-full h-11 bg-transparent border border-gray/50 rounded-lg text-gray placeholder-gray/50 focus:outline-none focus:ring-0 focus:border-gray"
            ) %>
            <div class="mt-2.5">
              <%= submit("Create",
                phx_disable_with: "Saving...",
                class:
                  "w-full h-11 focus:outline-none text-white px-4 rounded-lg disabled:opacity-50",
                style: "background-color: rgb(36, 24, 36);",
                disabled: !@valid_input?
              ) %>
            </div>
          </.form>
          <div class="mt-7 flex flex-row items-center justify-between">
            <hr class="basis-[44%] border-1 border-grayscale/50" />
            <p class="text-grayscale/50">or</p>
            <hr class="basis-[44%] border-1 border-grayscale/50" />
          </div>
          <.form
            id="upload-cargo-user"
            for={%{}}
            as={:cargo_user}
            class="column"
            phx-change="upload"
            phx-submit="save"
            phx-drop-target={@uploads.config.ref}
            phx-target={@myself}
          >
            <%= live_file_input(@uploads.config, style: "display: none") %>
            <input
              style="background-color: rgb(36, 24, 36);"
              class="w-full h-11 mt-2 bg-transparent text-white py-2 px-4 border border-white/0 rounded-lg flex items-center justify-center"
              type="button"
              value="Upload"
              onclick="event.target.parentNode.querySelector('input[type=file]').click()"
            />
            <%= if @invalid_upload? do %>
              <p class="flex items-center justify-center mt-3 text-md text-red-500">
                Keys are invalid or broken
              </p>
            <% end %>
          </.form>
        </div>
      <% end %>
    </div>
    """
  end

  def handle_event("validate", %{"user" => %{"name" => name}}, socket) do
    socket
    |> assign(:valid_input?, name |> String.trim() |> String.length() |> then(&(&1 >= 2)))
    |> noreply()
  end

  def handle_event("create", %{"user" => %{"name" => name}}, socket) do
    identity = User.login(name)
    content = identity |> Actor.new([], %{}) |> Actor.to_encrypted_json("")

    entry = %{
      client_last_modified: DateTime.utc_now() |> DateTime.to_unix(),
      client_name: name <> ".data",
      client_relative_path: nil,
      client_size: byte_size(content),
      client_type: "text/plain"
    }

    send(self(), {:admin, {:create_cargo_user, {identity, content, entry}}})

    socket
    |> noreply()
  end

  def handle_event("upload", _, socket) do
    socket
    |> noreply()
  end

  def handle_event("backup-keys", _, %{assigns: %{cargo_user: user}} = socket) do
    broker_key =
      Actor.new(user, [], %{})
      |> Actor.to_encrypted_json("")
      |> then(&{"#{user.name}.data", &1})
      |> Broker.store()

    socket
    |> push_event("chat:redirect", %{url: url(~p"/get/backup/#{broker_key}")})
    |> noreply()
  end

  def handle_progress(:config, %{done?: true} = entry, socket) do
    valid? =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        content = File.read!(path)

        {:ok,
         case validate_content(content) do
           :error ->
             false

           parsed ->
             identity = parsed |> then(fn %{me: me} -> me end)
             send(self(), {:admin, {:create_cargo_user, {identity, content, entry}}})
             true
         end}
      end)

    socket
    |> assign(:invalid_upload?, !valid?)
    |> noreply()
  end

  def handle_progress(_file, _entry, socket), do: socket |> noreply()

  defp validate_content("[[\"" <> _ = content) do
    Actor.from_json(content)
  rescue
    _ -> :error
  end

  defp validate_content(_content), do: :error
end
