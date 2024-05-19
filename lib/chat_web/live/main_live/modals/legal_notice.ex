defmodule ChatWeb.MainLive.Modals.LegalNotice do
  @moduledoc """
  Legal notice modal
  """
  use ChatWeb, :live_component

  alias Phoenix.LiveView.JS

  def render(assigns) do
    ~H"""
    <div id="legal-notice-modal">
      <div
        :if={!@hide}
        class="h-[100vh] bg-[#893d51] absolute z-50 w-full flex items-center justify-center text-lg text-[#7A727A]"
      >
        <div class="w-[90%] xl:w-[27%] bg-white rounded-xl p-6 flex flex-col gap-5">
          <p>
            - The creators of this app carry absolutely no access, control, or responsibility for the data uploaded.
            Use at your own risk.
          </p>
          <p>
            - No data at all is transferred anywhere else but within the local device and the storage physically
            plugged in to it, if not done otherwise explicitly by the user.
          </p>
          <p>
            - <span class="text-red-500">Warning!</span>
            This is a free demo intended for testing purposes, all
            features
            integrity is
            not guaranteed.
          </p>
          <div class="flex items-center gap-3 pl-3">
            <form
              phx-change={
                JS.hide(transition: "fade-out", to: "#legal-notice-modal") |> JS.push("accept")
              }
              phx-target={@myself}
            >
              <input class="scale-150 mr-1" type="checkbox" id="note" name="note" value="note" />
              <label class="text-sm text-black" for="note">
                By using you agree to accept the custom
                <a class="text-blue-700" href="/privacy-policy.html" target="_blank">
                  privacy policy & terms
                </a>
              </label>
            </form>
            <br />
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("accept", _, socket) do
    socket
    |> push_event("set-legal-notice-accepted", %{legal_notice_key: "agreementAccepted"})
    |> noreply()
  end
end
