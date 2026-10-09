defmodule Chat.Data.Shapes.VouchToken do
  @moduledoc "Shape behaviour implementation for vouch_token."

  alias Chat.Data.Schemas.VouchToken
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.Data.VouchToken.Validation
  alias Phoenix.Sync.Writer

  use Chat.Data.Shapes.Shape,
    persist: [
      upsert: &VouchTokenData.upsert_vouch_token/1,
      get: &VouchTokenData.get_vouch_token/3,
      lookup_key: [:kind, :issuer_hash, :subject_hash],
      validate_insert: &Validation.validate_vouch_token_insert/1,
      validate_update: &Validation.validate_vouch_token_update/2
    ]

  use Toolbox.OriginLog

  @impl true
  def shape_name, do: :vouch_token

  @impl true
  def schema_module, do: VouchToken

  @impl true
  def sync_required_parents(_op, %{issuer_hash: ih, subject_hash: sh}) do
    [{:user_card, ih}, {:user_card, sh}]
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, VouchToken,
      accept: [:insert, :update],
      check: &Validation.vouch_token_allowed(&1, user_pop_context),
      validate: &Validation.vouch_token_validate/3
    )
  end
end
