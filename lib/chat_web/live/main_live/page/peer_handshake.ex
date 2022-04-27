defmodule ChatWeb.MainLive.Page.PeerHandshake do
  @moduledoc "Peer handshake page"
  import Phoenix.LiveView, only: [assign: 3]

  alias Chat.Broker
  alias Chat.Log
  alias Chat.User
  alias Chat.Utils

  alias ChatWeb.Router.Helpers, as: Routes

  def init(%{assigns: %{}} = socket, user_id) do
    peer = User.by_id(user_id)

    socket
    |> assign(:mode, :peer_handshake)
    |> assign(:user_id, user_id)
    |> assign(:peer, peer)
    |> assign_qr()
  end

  def refresh(%{assigns: %{key: key}} = socket) do
    Broker.get(key)

    socket
    |> assign_qr()
  end

  def handle_peer_response(
        %{assigns: %{me: me, secret: secret, peer: peer}} = socket,
        peer_signed_message
      ) do
    if :peer_version == secret do
      :add_as_contact
      me |> Log.add_contact(peer)
    end

    socket
  end

  def close(socket) do
    Broker.get(socket.assigns.key)

    socket
    |> assign(:user_id, nil)
    |> assign(:peer, nil)
    |> assign(:key, nil)
    |> assign(:secret, nil)
    |> assign(:url, nil)
    |> assign(:qr, nil)
  end

  defp assign_qr(%{assigns: %{peer: peer}} = socket) do
    secret = UUID.uuid4()
    encrypted = Utils.encrypt(secret, peer)
    key = Broker.store({self(), encrypted})

    url = Routes.main_accept_peer_handshake_url(socket, :accept_handshake, key)

    qr =
      url
      |> QRCode.create!()
      |> QRCode.Svg.to_base64()

    socket
    |> assign(:secret, secret)
    |> assign(:key, key)
    |> assign(:url, url)
    |> assign(:qr, qr)
  end
end
