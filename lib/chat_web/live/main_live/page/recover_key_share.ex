defmodule ChatWeb.MainLive.Page.RecoverKeyShare do
  @moduledoc "Recover Key Share Page"
  use ChatWeb, :live_component

  alias Chat.KeyShare

  def mount(socket) do
    {:ok,
     socket
     |> assign(:shares, [])}
  end

  def handle_event("recover-key-load", _, socket) do
    socket |> noreply()
  end

  def handle_progress(:recover_keys, %{done?: true}, socket) do
    socket
    |> read_file()
    |> noreply()
  end

  def read_file(socket) do
    shares =
      consume_uploaded_entries(socket, :recover_keys, fn %{path: path}, entry ->
        {:ok, %{key: File.read!(path) |> Base.decode64!(), name: entry.client_name}}
      end)

    socket |> assign(:shares, shares)
  end

  def render(assigns) do
    ~H"""
    <div>
      <img class="vectorGroup bottomVectorGroup" src="/images/bottom_vector_group.svg" />
      <img class="vectorGroup topVectorGroup" src="/images/top_vector_group.svg" />
      <div class="flex flex-col items-center justify-center w-screen h-screen">
        <div class="container unauthenticated z-10">
          <div class="flex justify-center">
            <.icon id="logo" class="w-14 h-14 fill-white" />
          </div>
          <div class="left-0 mt-10">
            <a
              phx-click="login:import-own-keyring-close"
              class="x-back-target flex items-center justify-start"
            >
              <.icon id="arrowLeft" class="w-4 h-4 fill-white/70" />
              <p class="ml-2 text-sm text-white/70">Back to Log In</p>
            </a>
            <h1
              style="font-size: 28px; line-height: 34px;"
              class="mt-5 font-inter font-bold text-white"
            >
              Recover key from Social Sharing
            </h1>
            <p class="mt-2.5 font-inter text-sm text-white/70">
              Please, upload at least
              <a class="font-bold"><%= KeyShare.threshold() - Enum.count(@shares) %></a>
              share files to recover your key
            </p>
          </div>
          <%= if @step == :initial do %>
            <div class="row">
              <.form
                :let={_f}
                for={%{}}
                as={:recover_keys}
                id="recover-keys-form"
                class="column "
                phx-change="recover-key-load"
                phx-submit="recover-key-load"
                phx-target={@myself}
              >
                <%= live_file_input(@uploads.recover_keys, style: "display: none") %>
                <input
                  style="background-color: rgb(36, 24, 36);"
                  class="w-full h-11 mt-7 bg-transparent text-white py-2 px-4 border border-white/0 rounded-lg flex items-center justify-center"
                  type="button"
                  value="Upload Key Files"
                  onclick="event.target.parentNode.querySelector('input[type=file]').click()"
                />
                <%= for entry <- @uploads.recover_keys.entries do %>
                  <%= if entry.progress > 0 and entry.progress <= 100 do %>
                    <progress value={entry.progress} max="100"><%= entry.progress %>%</progress>
                  <% end %>
                  <%= for err <- upload_errors(@uploads.recover_keys, entry) do %>
                    <p class="alert alert-danger"><%= err %></p>
                  <% end %>
                <% end %>
              </.form>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
