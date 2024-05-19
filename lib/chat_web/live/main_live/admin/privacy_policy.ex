defmodule ChatWeb.MainLive.Admin.PrivacyPolicy do
  @moduledoc """
  Privacy policy editor
  """
  use ChatWeb, :live_component

  def mount(socket) do
    socket
    |> assign(:privacy_policy, load_privacy_policy())
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div id="privacy-policy-editor">
      Put raw html here <textarea id="privacy-policy" name="privacy-policy">{@privacy_policy}</textarea>

      <button phx-click="save" target={@myself}>Save</button>
    </div>
    """
  end

  defp load_privacy_policy do
    """
    <h1>Privacy Policy</h1>

    <p>Privacy Policy</p>
    """
  end

end
