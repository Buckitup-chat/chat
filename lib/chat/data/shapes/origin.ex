defmodule Chat.Data.Shapes.Origin do
  @moduledoc "Shape behaviour implementation for origin"

  alias Chat.Data.Origin, as: OriginData
  alias Chat.Data.Origin.Validation
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Types.OriginSignHash
  alias EnigmaPq
  alias Phoenix.Sync.Writer

  use Chat.Data.Shapes.Shape,
    persist: [
      upsert: &OriginData.upsert_origin/1,
      get: &OriginData.get_origin/1,
      lookup_key: :origin_hash,
      validate_insert: &Validation.validate_origin_insert/1,
      validate_update: &Validation.validate_origin_update/2
    ]

  use Toolbox.OriginLog

  @impl true
  def shape_name, do: :origin

  @impl true
  def schema_module, do: Origin

  @impl true
  def sync_required_parents(_op, %{origin_hash: oh, owner_hash: ow}) do
    [{:user_card, oh}, {:user_card, ow}]
  end

  @impl true
  def sync_derive_fields(%Origin{sign_b64: sign_b64} = origin) when is_binary(sign_b64) do
    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> OriginSignHash.from_binary()

    %{origin | sign_hash: sign_hash}
  end

  def sync_derive_fields(origin), do: origin

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, Origin,
      accept: [:insert, :update],
      check: &Validation.origin_allowed(&1, user_pop_context),
      validate: &Validation.origin_validate/3
    )
  end
end
