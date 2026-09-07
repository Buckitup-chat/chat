defmodule Chat.Data.Review.Validation do
  @moduledoc "Signature and integrity validation for review operations."

  import Chat.Db, only: [repo: 0]

  alias Chat.Data.Origin, as: OriginData
  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.Review.Versioning
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.Schemas.Review
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  # --- Peer sync validation ---

  def validate_review_insert(review_struct) do
    %Review{}
    |> Review.create_changeset(Map.from_struct(review_struct))
    |> UserValidation.validate_signature()
    |> validate_origin_exists(review_struct.origin_hash)
  end

  def validate_review_update(existing, review_struct) do
    attrs =
      review_struct
      |> Map.from_struct()
      |> Map.take([
        :content_b64,
        :deleted_flag,
        :parent_sign_hash,
        :owner_timestamp,
        :sign_b64,
        :sign_hash
      ])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> Review.update_changeset(attrs)
    |> UserValidation.validate_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
  end

  # --- HTTP ingestion ---

  def review_allowed(operation, %{challenge: challenge, signature: signature}) do
    author_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["author_hash"] || changes[:author_hash]

        %Operation{operation: :update, data: %{"author_hash" => hash}} ->
          hash
      end

    with %{sign_pkey: sign_pkey} <- UserData.get_card(author_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  def review_validate(review, changes, op) do
    case op do
      :insert ->
        origin_hash = changes["origin_hash"] || changes[:origin_hash]

        review
        |> Review.create_changeset(changes)
        |> UserValidation.validate_signature()
        |> validate_origin_exists(origin_hash)

      :update ->
        review
        |> Review.update_changeset(changes)
        |> UserValidation.validate_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
    end
  end

  # --- HTTP ingestion with versioning ---

  def review_validate_with_versioning(review, changes, op) do
    changeset =
      case op do
        :insert ->
          origin_hash = changes["origin_hash"] || changes[:origin_hash]

          review
          |> Review.create_changeset(changes)
          |> UserValidation.validate_signature()
          |> validate_origin_exists(origin_hash)

        :update ->
          review
          |> Review.update_changeset(changes)
          |> UserValidation.validate_signature()
      end

    case {op, changeset.valid?} do
      {:insert, true} ->
        with {:ok, new_review} <- Ecto.Changeset.apply_action(changeset, :insert),
             %Review{} = existing <- ReviewData.get_review(new_review.review_hash) do
          handle_insert_with_versioning(changeset, existing, new_review)
        else
          _ -> changeset
        end

      {:update, true} ->
        case Ecto.Changeset.apply_action(changeset, :update) do
          {:ok, new_review} ->
            changeset
            |> validate_edit_allowed(changeset.data)
            |> handle_update_with_versioning(changeset.data, new_review)

          _ ->
            changeset
        end

      _ ->
        changeset
    end
  end

  defp handle_insert_with_versioning(changeset, existing, new_review) do
    if new_review.owner_timestamp > existing.owner_timestamp do
      Ecto.Changeset.put_change(changeset, :parent_sign_hash, existing.sign_hash)
    else
      Ecto.Changeset.add_error(changeset, :owner_timestamp, "timestamp not newer")
    end
  end

  defp handle_update_with_versioning(changeset, existing, new_review) do
    case changeset do
      %{valid?: false} ->
        changeset

      _ ->
        if new_review.owner_timestamp > existing.owner_timestamp do
          Ecto.Changeset.put_change(changeset, :parent_sign_hash, existing.sign_hash)
        else
          Ecto.Changeset.add_error(changeset, :owner_timestamp, "timestamp not newer")
        end
    end
  end

  defp validate_edit_allowed(changeset, existing) do
    with %{moderation_mode: :pre} <- OriginData.get_origin(existing.origin_hash),
         %{} <- PublicPasswordData.get_latest_for_review(existing.review_hash) do
      Ecto.Changeset.add_error(changeset, :review_hash, "editing locked after pre-moderation")
    else
      _ -> changeset
    end
  end

  def review_pre_apply_versioning(multi, changeset, _context) do
    cond do
      changeset.valid? ->
        archive_review_if_newer(multi, changeset)

      timestamp_not_newer?(changeset) ->
        archive_old_review_version(multi, changeset)

      true ->
        multi
    end
  end

  defp timestamp_not_newer?(changeset) do
    Keyword.has_key?(changeset.errors, :owner_timestamp)
  end

  defp archive_review_if_newer(multi, changeset) do
    case Ecto.Changeset.apply_action(changeset, changeset.action || :insert) do
      {:ok, %{owner_timestamp: new_ts} = new_review} ->
        case fetch_existing_review(changeset, new_review) do
          %Review{owner_timestamp: existing_ts} = existing when new_ts > existing_ts ->
            Versioning.archive_multi_insert(multi, :archive_existing, existing)

          _ ->
            multi
        end

      _ ->
        multi
    end
  end

  defp fetch_existing_review(%{action: :update, data: data}, _new_review), do: data

  defp fetch_existing_review(_changeset, new_review) do
    repo().get(Review, new_review.review_hash)
  end

  defp archive_old_review_version(multi, changeset) do
    case Ecto.Changeset.apply_action(%{changeset | action: :insert}, :insert) do
      {:ok, new_review} ->
        Versioning.archive_multi_insert(multi, :archive_old_version, new_review)

      _ ->
        multi
    end
  end

  # --- Origin existence check ---

  defp validate_origin_exists(changeset, origin_hash) when is_binary(origin_hash) do
    case OriginData.get_origin(origin_hash) do
      nil ->
        Ecto.Changeset.add_error(changeset, :origin_hash, "origin does not exist")

      _origin ->
        changeset
    end
  end

  defp validate_origin_exists(changeset, _origin_hash), do: changeset
end
