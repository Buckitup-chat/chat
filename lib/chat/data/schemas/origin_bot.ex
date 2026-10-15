defmodule Chat.Data.Schemas.OriginBot do
  @moduledoc "Ecto schema for origin review bots, signed by origin identity."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.Types.OriginBotSignHash
  alias Chat.Data.Types.UserHash
  alias Chat.Data.User

  @primary_key {:bot_hash, UserHash, []}

  @create_fields [
    :bot_hash,
    :origin_hash,
    :secret,
    :encrypted_identity,
    :deleted_flag,
    :owner_timestamp,
    :sign_b64,
    :sign_hash
  ]
  @create_required @create_fields

  @update_fields [:deleted_flag, :owner_timestamp, :sign_b64, :sign_hash]

  schema "origin_bots" do
    field(:origin_hash, UserHash)
    field(:secret, :binary)
    field(:encrypted_identity, :binary)
    field(:deleted_flag, :boolean, default: false)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
    field(:sign_hash, OriginBotSignHash)
  end

  def create_changeset(bot, attrs) do
    bot
    |> cast(attrs, @create_fields)
    |> validate_required(@create_required)
    |> unique_constraint(:bot_hash, name: :origin_bots_pkey)
  end

  def update_changeset(bot, attrs) do
    bot
    |> cast(attrs, @update_fields)
    |> validate_required(@update_fields)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(bot) do
      bot
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :sign_hash, :__meta__])
    end

    def signing_key(bot), do: User.get_card(bot.origin_hash).sign_pkey

    def signature(bot), do: bot.sign_b64
  end
end
