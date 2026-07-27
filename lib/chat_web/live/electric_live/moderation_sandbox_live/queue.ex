defmodule ChatWeb.ElectricLive.ModerationSandboxLive.Queue do
  @moduledoc """
  Reads the origin's moderation queue through Electric shape endpoints.

  Fetches `review`, `review_public_passwords` and both right tables for a single
  origin and hands them to `Entries` for decryption and classification.
  """

  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.Schemas.UserCard
  alias ChatWeb.ElectricLive.ModerationSandboxLive.Entries
  alias Electric.Client.Message

  @doc "Origin row and its user_cards row — used to verify the imported identity."
  def fetch_origin_context(origin_hash, base_url) do
    client = client(base_url)

    %{
      origin: client |> rows("origins", Origin, origin_hash) |> List.first(),
      card: client |> rows("user_cards", UserCard, origin_hash, "user_hash") |> List.first()
    }
  end

  def load(origin_hash, crypt_skey, base_url) do
    client = client(base_url)
    reviews = rows(client, "review", Review, origin_hash)
    passwords = rows(client, "review_public_passwords", ReviewPublicPassword, origin_hash)
    post_rights = rows(client, "review_post_right", ReviewPostRight, origin_hash)
    revoke_rights = rows(client, "review_revoke_right", ReviewRevokeRight, origin_hash)

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

  defp client(base_url) do
    Electric.Client.new!(endpoint: base_url <> "/electric/v1/shapes")
  end

  defp rows(client, table, schema, hash, column \\ "origin_hash") do
    shape =
      Electric.Client.ShapeDefinition.new!(table,
        where: "#{column} = $1",
        params: [hash],
        parser: {Electric.Client.EctoAdapter, schema}
      )

    client
    |> Electric.Client.stream(shape, live: false, replica: :full)
    |> Enum.reduce_while([], fn
      %Message.ChangeMessage{headers: %{operation: :insert}, value: value}, acc ->
        {:cont, [value | acc]}

      %Message.ControlMessage{control: :up_to_date}, acc ->
        {:halt, acc}

      _message, acc ->
        {:cont, acc}
    end)
  end
end
