defmodule Chat.Data.Shapes.Origin do
  @moduledoc "Shape behaviour implementation for origin"

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.Origin, as: OriginData
  alias Chat.Data.Origin.Validation
  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Types.OriginSignHash
  alias EnigmaPq
  alias Phoenix.Sync.Writer

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
  def sync_persist(operation, origin) do
    case operation do
      :insert ->
        origin
        |> Validation.validate_origin_insert()
        |> persist_insert(origin)

      :update ->
        persist_update(origin)
    end
  end

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, Origin,
      accept: [:insert, :update],
      check: &Validation.origin_allowed(&1, user_pop_context),
      validate: &Validation.origin_validate/3
    )
  end

  defp persist_insert(changeset, origin) do
    case changeset do
      %{valid?: true} ->
        OriginData.upsert_origin(changeset)

      %{valid?: false} = cs ->
        log("Invalid origin insert signature: #{inspect(cs.errors)}", :warning)
        {:ok, origin}
    end
  end

  defp persist_update(origin) do
    case OriginData.get_origin(origin.origin_hash) do
      nil ->
        {:ok, origin}

      existing ->
        existing
        |> Validation.validate_origin_update(origin)
        |> apply_changeset(origin)
    end
  end

  defp apply_changeset(changeset, origin) do
    case changeset do
      %{valid?: true} ->
        %Origin{}
        |> Origin.create_changeset(origin |> Map.from_struct())
        |> OriginData.upsert_origin()

      %{valid?: false, action: :ignore} ->
        {:ok, origin}

      %{valid?: false} = cs ->
        log("Invalid origin update signature: #{inspect(cs.errors)}", :warning)
        {:ok, origin}
    end
  end
end
