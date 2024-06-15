defmodule ChatWeb.MainLive.Admin.PrivacyPolicy do
  @moduledoc """
  Privacy policy editor
  """
  use ChatWeb, :live_component

  alias Phoenix.LiveView.JS

  alias Chat.AdminRoom

  def mount(socket) do
    socket
    |> assign(:privacy_policy, load_privacy_policy())
    |> ok()
  end

  def handle_event("save", %{"privacy-policy" => privacy_policy}, socket) do
    text = privacy_policy |> String.trim()
    save_privacy_policy(text)

    socket
    |> assign(:privacy_policy, text)
    |> noreply()
  end

  def render(assigns) do
    ~H"""
    <div id="privacy-policy-editor">
      <div>
        <a
          data-role="expand-button"
          phx-click={
            JS.add_class("w-[85vw]", to: "#privacy-policy-editor form")
            |> JS.add_class("h-[70vh]", to: "#privacy-policy")
            |> JS.hide(to: "#privacy-policy-editor [data-role=expand-button]")
            |> JS.show(to: "#privacy-policy-editor [data-role=collapse-button]")
          }
        >
          Expand
        </a>
        <a
          data-role="collapse-button"
          class="hidden"
          phx-click={
            JS.remove_class("w-[85vw]", to: "#privacy-policy-editor form")
            |> JS.remove_class("h-[70vh]", to: "#privacy-policy")
            |> JS.hide(to: "#privacy-policy-editor [data-role=collapse-button]")
            |> JS.show(to: "#privacy-policy-editor [data-role=expand-button]")
          }
        >
          Collapse
        </a>
      </div>
      <form phx-submit="save" phx-target={@myself}>
        <textarea id="privacy-policy" name="privacy-policy" class="w-full h-full"><%= @privacy_policy %></textarea>
        <div>
          <button>Save</button>
        </div>
      </form>
    </div>
    """
  end

  defp load_privacy_policy do
    AdminRoom.get_privacy_policy_text()
  end

  defp save_privacy_policy(privacy_policy) do
    AdminRoom.store_privacy_policy_text(privacy_policy)
  end
end
