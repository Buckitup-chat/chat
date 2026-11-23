defmodule ChatWeb.ElectricLive.WriteTokenLinks do
  @moduledoc """
  Full `/r/<nonce>` links and QR codes for write tokens of bots running on this node.

  Token rows carry only `nonce_hash` and the bot-encrypted `nonce_enc_b64`; the
  running bot decrypts it (`Worker.reveal_nonce/2`), so keys stay in the Worker.
  Shared by the origin and moderation sandboxes.
  """

  use Phoenix.Component

  alias Chat.ReviewBot.Worker
  alias Chat.Utils

  def attach(tokens), do: Enum.map(tokens, &attach_link/1)

  defp attach_link(%{deleted_flag: false, bot_hash: bot, nonce_enc_b64: enc} = token)
       when is_binary(bot) and is_binary(enc) do
    case Worker.reveal_nonce(bot, token) do
      {:ok, nonce} ->
        url = "#{ChatWeb.Endpoint.url()}/r/#{nonce}"
        Map.merge(token, %{url: url, qr: Utils.qr_base64_from_url(url)})

      {:error, _reason} ->
        token
    end
  end

  defp attach_link(token), do: token

  attr :token, :map, required: true

  def token_link(assigns) do
    ~H"""
    <div :if={@token[:url]} class="mt-2 flex items-start gap-3">
      <img class="w-24 h-24 t-token-qr" src={"data:image/svg+xml;base64, #{@token.qr}"} />
      <a href={@token.url} target="_blank" class="font-mono text-blue-600 hover:underline break-all">
        {@token.url}
      </a>
    </div>
    """
  end
end
