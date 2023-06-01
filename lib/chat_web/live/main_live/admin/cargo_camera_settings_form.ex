defmodule ChatWeb.MainLive.Admin.CargoCameraSettingsForm do
  @moduledoc """
  Handles managment of cargo camera urls
  """

  use ChatWeb, :live_component

  alias Chat.AdminRoom

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(cargo_settings: assigns.cargo_settings)
     |> assign(:url_input_len, 0)
     |> assign(:response_error, nil)}
  end

  def handle_event(
        "input-change",
        %{
          "camera_url" => %{
            "url" => url
          }
        } = _params,
        socket
      ) do
    {:noreply, assign(socket, :url_input_len, url |> String.trim() |> String.length())}
  end

  def handle_event(
        "delete",
        %{"url" => url} = _params,
        %{assigns: %{cargo_settings: cargo_settings}} = socket
      ) do
    %{cargo_settings | camera_urls: cargo_settings.camera_urls -- [url]}
    |> AdminRoom.store_cargo_settings()

    send(self(), :update_cargo_settings)
    {:noreply, socket}
  end

  def handle_event("close_error", _params, socket) do
    {:noreply, assign(socket, :response_error, nil)}
  end

  def handle_event(
        "save",
        %{
          "camera_url" => %{
            "url" => url
          }
        } = _params,
        socket
      ) do
    with {:ok, %HTTPoison.Response{} = response} <- url |> String.trim() |> HTTPoison.get(),
         %{status_code: status_code, headers: headers} <- response do
      case {status_code, is_image(headers)} do
        {200, true} ->
          socket.assigns.cargo_settings |> save(url)
          send(self(), :update_cargo_settings)

          {:noreply, socket |> assign(:response_error, nil)}

        {200, false} ->
          {:noreply, assign(socket, :response_error, "Response content type is not image")}

        _ ->
          {:noreply, assign(socket, :response_error, "Bad response from camera url")}
      end
    else
      {:error, %HTTPoison.Error{reason: _reason}} ->
        {:noreply, assign(socket, :response_error, "Unable to get response")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col max-w-xs">
      <section class="flex flex-row mt-4">
        <.form
          :let={f}
          for={%{}}
          as={:camera_url}
          id="camera-url-form"
          phx-submit="save"
          phx-change="input-change"
          phx-target={@myself}
          class="w-full"
        >
          <div class="flex flex-row">
            <%= text_input(f, :url,
              placeholder: "url",
              class: "w-full h-8 bg-transparent border border-black/50 rounded-lg"
            ) %>

            <div class="mx-0.5">
              <%= submit("Save",
                phx_disable_with: "...",
                class:
                  "h-8 focus:outline-none text-white px-4 rounded-lg <> #{if(@url_input_len < 10, do: "opacity-60")}",
                style: "background-color: rgb(36, 24, 36);",
                disabled: @url_input_len < 10
              ) %>
            </div>
          </div>
        </.form>
      </section>
      <.response_error myself={@myself} response_error={@response_error} />
      <.show_urls myself={@myself} cargo_settings={@cargo_settings} />
    </div>
    """
  end

  def show_urls(assigns) do
    ~H"""
    <section class="flex flex-row mt-2">
      <div :if={Map.has_key?(@cargo_settings, :camera_urls)}>
        <ul class="max-h-60 overflow-y-auto" id="camera-urls-list" phx-target={@myself}>
          <%= for url <- @cargo_settings.camera_urls do %>
            <span class="inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs text-gray-600 ring-1 ring-inset ring-gray-500/10 t-camera-url">
              <%= case String.length(url) > 45 do
                true -> url_shorten(url)
                false -> url
              end %>
              <span phx-click="delete" phx-value-url={url} phx-target={@myself}>
                <.icon id="delete" class="w-4 h-4 ml-1.5 flex fill-grayscale cursor-pointer" />
              </span>
            </span>
          <% end %>
        </ul>
      </div>
    </section>
    """
  end

  defp response_error(assigns) do
    ~H"""
    <div
      :if={@response_error != nil}
      class="flex flex-row justify-between mt-1 bg-red-100 border border-red-400 text-red-700 px-2 rounded relative"
      role="alert"
    >
      <span>
        <%= @response_error %>
      </span>
      <a phx-click="close_error" phx-target={@myself}>
        <.icon id="close" class="w-4 h-4 mr-1.5 mt-1 fill-grayscale cursor-pointer" />
      </a>
    </div>
    """
  end

  defp is_image(headers),
    do: Enum.any?(headers, fn {k, v} -> k == "Content-Type" && String.match?(v, ~r/^image\//) end)

  defp save(cargo_settings, url) do
    cargo_settings =
      case Map.has_key?(cargo_settings, :camera_urls) do
        true -> Map.put(cargo_settings, :camera_urls, [url | cargo_settings.camera_urls])
        _ -> Map.put_new(cargo_settings, :camera_urls, [url])
      end

    :ok = AdminRoom.store_cargo_settings(cargo_settings)
  end

  defp url_shorten(url),
    do:
      String.slice(url, 0, 25) <>
        "..." <> String.slice(url, String.length(url) - 20, String.length(url))
end
