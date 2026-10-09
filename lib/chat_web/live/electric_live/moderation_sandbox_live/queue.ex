defmodule ChatWeb.ElectricLive.ModerationSandboxLive.Queue do
  @moduledoc """
  Reads the origin's moderation queue through Electric shape endpoints.

  Fetches `review`, `review_public_passwords` and both right tables for a single
  origin and hands them to `Entries` for decryption and classification.
  """

  alias ChatWeb.ElectricLive.ModerationSandboxLive.Entries
  alias ChatWeb.ElectricLive.SandboxHttp

  @doc "Origin row and its user_cards row — used to verify the imported identity."
  def fetch_origin_context(origin_hash, base_url, auth) do
    %{
      origin:
        case fetch_first(base_url, "origins", "origin_hash='#{origin_hash}'", auth) do
          nil -> nil
          row -> parse_origin(row)
        end,
      card: fetch_first(base_url, "user_cards", "user_hash='#{origin_hash}'", auth)
    }
  end

  def load(origin_hash, crypt_skey, base_url, auth) do
    reviews = fetch_rows(base_url, "review", origin_hash, auth)
    passwords = fetch_rows(base_url, "review_public_passwords", origin_hash, auth)
    post_rights = fetch_rows(base_url, "review_post_right", origin_hash, auth)
    revoke_rights = fetch_rows(base_url, "review_revoke_right", origin_hash, auth)

    %{
      entries: Entries.build(reviews, passwords, post_rights, revoke_rights, crypt_skey),
      counts: %{
        reviews: length(reviews),
        passwords: length(passwords),
        post_rights: length(post_rights),
        revoke_rights: length(revoke_rights)
      }
    }
  end

  # --- Private ---

  defp fetch_rows(base_url, table, origin_hash, auth) do
    case SandboxHttp.fetch_shape_gated(base_url, table, "origin_hash='#{origin_hash}'", auth) do
      {:ok, rows, _logs} -> rows
      {:error, _reason, _logs} -> []
    end
  end

  defp fetch_first(base_url, table, where, auth) do
    case SandboxHttp.fetch_shape_gated(base_url, table, where, auth) do
      {:ok, [row | _], _logs} -> row
      _ -> nil
    end
  end

  defp parse_origin(row) do
    %{
      name: row["name"],
      moderation_mode: row["moderation_mode"],
      deleted_flag: row["deleted_flag"] in [true, "true", "t"]
    }
  end
end
