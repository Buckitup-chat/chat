defmodule ChatWeb.MainLive.Page.ImportKeyRing do
  @moduledoc "Import Key Ring Page"
  import Phoenix.LiveView, only: [assign: 3]

  alias Chat.KeyRingTokens
  alias ChatWeb.MainLive.Page
  alias ChatWeb.Router.Helpers, as: Routes

  def init(socket) do
    {uuid, code} = KeyRingTokens.create()

    url = Routes.main_index_url(socket, :export, uuid)
    qr_settings = %QRCode.SvgSettings{qrcode_color: "#ffffff", background_opacity: 0}

    qr =
      url
      |> QRCode.create!()
      |> QRCode.Svg.to_base64(qr_settings)

    socket
    |> assign(:mode, :import_key_ring)
    |> assign(:url, url)
    |> assign(:encoded_qr_code, qr)
    |> assign(:code, code)
  end

  def save_key_ring(socket, {me, rooms}) do
    socket
    |> Page.Login.load_user(me, rooms)
  end

  def close(socket) do
    socket
    |> assign(:url, nil)
    |> assign(:encoded_qr_code, nil)
    |> assign(:code, nil)
  end
end
