defmodule ChatWeb.ElectricLive.IdentityCheck do
  @moduledoc """
  Flags an imported identity whose user card is not on this server.

  Every ingest is authorised against the issuer's `user_cards` row, so without it
  all writes fail with an opaque 400 "Invalid operation". The flag lives on the
  identity map (`:on_server`) so sandboxes need no extra assigns.
  """

  alias ChatWeb.ElectricLive.SandboxHttp

  def mark_on_server(identity, base_url) do
    auth = %{user_hash: identity.user_hash, sign_skey: identity.sign_skey}
    Map.put(identity, :on_server, card_on_server?(identity.user_hash, base_url, auth))
  end

  defp card_on_server?(user_hash, base_url, auth) do
    case SandboxHttp.fetch_shape_gated(
           base_url,
           "user_cards",
           "user_hash='#{user_hash}'",
           auth
         ) do
      {:ok, rows, _logs} ->
        Enum.any?(rows, &(&1["deleted_flag"] not in [true, "true", "t"]))

      {:error, _reason, _logs} ->
        false
    end
  end
end
