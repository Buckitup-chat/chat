defmodule Chat.Data.Shapes.OriginSetting do
  @moduledoc "Shape behaviour implementation for origin_setting"

  alias Chat.Data.OriginSetting, as: OriginSettingData
  alias Chat.Data.OriginSetting.Validation
  alias Chat.Data.Schemas.OriginSetting
  alias Chat.Pq.WriteGate
  alias Phoenix.Sync.Writer

  use Chat.Data.Shapes.Shape,
    persist: [
      upsert: &OriginSettingData.upsert_origin_setting/1,
      get: &OriginSettingData.get_origin_setting/2,
      lookup_key: [:origin_hash, :key],
      validate_insert: &Validation.validate_origin_setting_insert/1,
      validate_update: &Validation.validate_origin_setting_update/2
    ]

  use Toolbox.OriginLog

  @impl true
  def shape_name, do: :origin_setting

  @impl true
  def schema_module, do: OriginSetting

  @impl true
  def sync_required_parents(_op, %{origin_hash: oh}) do
    [{:user_card, oh}, {:origin, oh}]
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, OriginSetting,
      accept: [:insert, :update],
      check:
        WriteGate.and_gate(
          &Validation.origin_setting_allowed(&1, user_pop_context),
          :origin_setting,
          owner: "origin_hash"
        ),
      validate: &Validation.origin_setting_validate/3
    )
  end
end
