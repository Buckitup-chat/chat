defmodule ChatWeb.ElectricLive.WriteTokenLinks do
  @moduledoc """
  Full `/r/<nonce>` links and QR codes for an origin's invitation tokens.

  Token rows carry only `nonce_hash` and the bot-encrypted `nonce_enc_b64`. Like a
  frontend, the sandbox decrypts client-side: the origin's `crypt_skey` unwraps each
  bot identity from its `origin_bots` row, whose `crypt_skey` decrypts the nonce.
  Only live, unbound tokens get a link — a reviewer's bound copy stays hidden.
  Shared by the origin and moderation sandboxes.
  """

  use Phoenix.Component

  alias Chat.Data.Types.ReviewWriteTokenNonceHash
  alias Chat.ReviewBot.Identity
  alias Chat.Utils

  def attach(tokens, bots, origin_crypt_skey, base_url) do
    keys = bot_crypt_keys(bots, origin_crypt_skey)
    Enum.map(tokens, &attach_link(&1, keys, base_url))
  end

  defp bot_crypt_keys(bots, origin_crypt_skey) do
    bots
    |> Enum.flat_map(fn
      %{deleted_flag: false, secret_b64: secret, encrypted_identity_b64: encrypted} = bot
      when is_binary(secret) and is_binary(encrypted) ->
        case Identity.unwrap(secret, encrypted, origin_crypt_skey) do
          {:ok, identity} -> [{bot.bot_hash, identity.crypt_skey}]
          _ -> []
        end

      _bot ->
        []
    end)
    |> Map.new()
  end

  defp attach_link(
         %{deleted_flag: false, user_hash: nil, bot_hash: bot, nonce_enc_b64: enc} = token,
         keys,
         base_url
       )
       when is_map_key(keys, bot) and is_binary(enc) do
    with {:ok, nonce} <- Identity.unwrap_nonce(enc, Map.fetch!(keys, bot)),
         true <- ReviewWriteTokenNonceHash.from_nonce(nonce) == token.nonce_hash do
      url = "#{base_url}/r/#{nonce}"
      Map.merge(token, %{url: url, qr: Utils.qr_base64_from_url(url)})
    else
      _ -> token
    end
  end

  defp attach_link(token, _keys, _base_url), do: token

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
