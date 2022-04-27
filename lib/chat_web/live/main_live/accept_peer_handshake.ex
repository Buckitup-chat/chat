defmodule ChatWeb.MainLive.AcceptPeerHandshake do
  @moduledoc "Accept Liveview"
  use ChatWeb, :live_view

  alias Phoenix.LiveView.JS

  alias ChatWeb.MainLive.Page

  @impl true
  def mount(params, _session, socket) do
    Process.flag(:sensitive, true)

    if connected?(socket) do
      socket
      |> Page.AcceptPeerHandshake.init(params["key"])
      |> Page.Login.check_stored()
      |> ok()
    else
      socket
      |> ok()
    end
  end

  @impl true
  def handle_event("restoreAuth", nil, socket), do: socket |> noreply()

  def handle_event("restoreAuth", data, socket) do
    socket
    |> Page.Login.load_user(data)
    |> Page.AcceptPeerHandshake.show()
    |> noreply()
  end

  @impl true
  def render(assigns) do
    ~H"""
      <div style="display: none;" id="session-link" phx-hook="LocalStateStore"></div>
      <%= unless connected?(@socket) do %>
      <% else %>
        <%= if @is_ready? do %>
          <a class="button button-outline float-right" type="button" href="javascript:window.close()">Close</a>
          <%= if @is_good_key? do %>
            <h2>Accept handshake of <%= @peer.name %> ? </h2>

          <% else %>
            <h2>Invalid Link</h2>
            <p> Ask peer to provide a new one </p>
          <% end %> 
        <% else %>
          <h2>Logging in...</h2>
          <p>Not logged in </p>
        <% end %> 
      <% end %>
    """
  end
end
