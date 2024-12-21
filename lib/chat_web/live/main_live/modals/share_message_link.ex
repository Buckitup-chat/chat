defmodule ChatWeb.MainLive.Modals.ShareMessageLink do
  @moduledoc "Share qr and link of message"
  use ChatWeb, :live_component
  alias Phoenix.LiveView.JS

  def mount(socket) do
    socket |> assign(:button_text, "Copy") |> ok()
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-base font-bold text-grayscale">Share message link</h1>
      <div class="border rounded border-white/10 rounded-xl p-10">
        <a href={@url} target="_blank">
          <img class="w-full" src={"data:image/svg+xml;base64, #{@encoded_qr_code}"} />
        </a>
      </div>
      <div class="flex flex-row">
        <input class="w-4/5 rounded-md" id="message-url" type="text" value={@url} readonly />
        <button
          class="ml-1 w-1/5 bg-grayscale focus:outline-none text-white rounded-md disabled:opacity-25"
          id="copy-button"
          phx-target={@myself}
          phx-click={
            JS.push("copy")
            |> JS.dispatch("phx:copy", to: "#message-url")
            |> JS.set_attribute({"disabled", "true"}, to: "#copy-button")
          }
        >
          {@button_text}
        </button>
      </div>
    </div>
    """
  end

  def handle_event("copy", _, socket) do
    socket |> assign(:button_text, "Copied") |> noreply()
  end
end
