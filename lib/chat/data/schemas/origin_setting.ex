defmodule Chat.Data.Schemas.OriginSetting do
  @moduledoc "Ecto schema for per-origin key-value settings, signed by origin identity."

  use Ecto.Schema
  import Ecto.Changeset

  alias Chat.Data.User

  @primary_key false

  @fields [:origin_hash, :key, :value, :deleted_flag, :owner_timestamp, :sign_b64]
  @update_fields [:value, :deleted_flag, :owner_timestamp, :sign_b64]

  schema "origin_settings" do
    field(:origin_hash, Chat.Data.Types.UserHash, primary_key: true)
    field(:key, :string, primary_key: true)
    field(:value, :string)
    field(:deleted_flag, :boolean, default: false)
    field(:owner_timestamp, :integer)
    field(:sign_b64, :binary)
  end

  def create_changeset(setting, attrs) do
    setting
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_value()
    |> unique_constraint([:origin_hash, :key], name: :origin_settings_pkey)
  end

  def update_changeset(setting, attrs) do
    setting
    |> cast(attrs, @update_fields)
    |> validate_required(@update_fields)
    |> validate_value()
  end

  defp validate_value(changeset) do
    case get_field(changeset, :key) do
      "review_access" ->
        validate_inclusion(changeset, :value, ["open", "invite_only"])

      "review_token_ttl_days" ->
        validate_positive_integer(changeset, :value, 1..365)

      _ ->
        changeset
    end
  end

  defp validate_positive_integer(changeset, field, first..last//1) do
    validate_change(changeset, field, fn _field, value ->
      case Integer.parse(value) do
        {int, ""} when int >= first and int <= last -> []
        _ -> [{field, "must be an integer in #{first}..#{last}"}]
      end
    end)
  end

  defimpl Chat.Data.User.Validation.TimestampedData, for: __MODULE__ do
    def existing_timestamp(%{owner_timestamp: timestamp}), do: timestamp
  end

  defimpl Chat.Data.Integrity.Signable, for: __MODULE__ do
    def signable_fields(setting) do
      setting
      |> Map.from_struct()
      |> Map.drop([:sign_b64, :__meta__])
    end

    def signing_key(setting), do: User.get_card(setting.origin_hash).sign_pkey

    def signature(setting), do: setting.sign_b64
  end
end
