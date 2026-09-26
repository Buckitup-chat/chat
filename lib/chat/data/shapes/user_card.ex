defmodule Chat.Data.Shapes.UserCard do
  @moduledoc "Shape behaviour implementation for user_card"

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.User
  alias Chat.Data.User.Validation
  alias Chat.Pq.OwnerBootstrap
  alias Chat.Pq.WriteGate
  alias Phoenix.Sync.Writer

  @impl true
  def shape_name, do: :user_card

  @impl true
  def schema_module, do: UserCard

  @impl true
  def sync_required_parents(_op, _card), do: []

  @impl true
  def sync_persist(operation, card) do
    case operation do
      :insert ->
        card
        |> Validation.validate_user_card_insert()
        |> persist_insert(card)

      :update ->
        persist_update(card)
    end
  end

  @impl true
  def sync_after_persist(:insert, %UserCard{user_hash: user_hash, sign_pkey: sign_pkey}, _opts) do
    OwnerBootstrap.maybe_register_owner(user_hash, sign_pkey)
    :ok
  end

  @impl true
  def sync_after_persist(_operation, _struct, _opts), do: :ok

  @impl true
  def ingest_configure_writer(writer, user_pop_context) do
    Writer.allow(writer, UserCard,
      accept: [:insert, :update],
      check: &Validation.user_card_allowed(&1, user_pop_context),
      validate: &Validation.user_card_validate/3
    )
  end

  defp persist_update(card) do
    case User.get_card(card.user_hash) do
      nil ->
        {:ok, card}

      existing ->
        existing
        |> Validation.validate_user_card_update(card)
        |> apply_changeset(card)
    end
  end

  defp persist_insert(changeset, card) do
    case changeset do
      %{valid?: true} ->
        User.upsert_card(changeset)

      %{valid?: false} ->
        log(
          "Invalid user_card insert signature for #{card.user_hash}: #{inspect(changeset.errors)}",
          :warning
        )

        {:ok, card}
    end
  end

  defp apply_changeset(changeset, card) do
    case changeset do
      %{valid?: true} ->
        User.update_card(changeset)

      %{valid?: false} ->
        log(
          "Invalid user_card signature for #{card.user_hash}: #{inspect(changeset.errors)}",
          :warning
        )

        {:ok, card}
    end
  end
end
