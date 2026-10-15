defmodule Chat.Data.Shapes.OriginBot do
  @moduledoc "Shape behaviour implementation for origin_bot"

  alias Chat.Data.OriginBot, as: OriginBotData
  alias Chat.Data.OriginBot.Validation
  alias Chat.Data.Schemas.OriginBot
  alias Chat.Pq.WriteGate
  alias Phoenix.Sync.Writer

  use Chat.Data.Shapes.Shape,
    persist: [
      upsert: &OriginBotData.upsert_origin_bot/1,
      get: &OriginBotData.get_origin_bot/1,
      lookup_key: :bot_hash,
      validate_insert: &Validation.validate_origin_bot_insert/1,
      validate_update: &Validation.validate_origin_bot_update/2
    ]

  use Toolbox.OriginLog

  @impl true
  def shape_name, do: :origin_bot

  @impl true
  def schema_module, do: OriginBot

  @impl true
  def sync_required_parents(_op, %{origin_hash: oh, bot_hash: bh}) do
    [{:user_card, oh}, {:origin, oh}, {:user_card, bh}]
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, OriginBot,
      accept: [:insert, :update],
      check:
        WriteGate.and_gate(
          &Validation.origin_bot_allowed(&1, user_pop_context),
          :origin_bot,
          owner: "origin_hash"
        ),
      validate: &Validation.origin_bot_validate/3
    )
  end
end
