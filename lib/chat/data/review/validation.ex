defmodule Chat.Data.Review.Validation do
  @moduledoc "Signature and integrity validation for review operations."

  alias Chat.Data.Origin, as: OriginData
  alias Chat.Data.OriginSetting
  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.Review.Versioning
  alias Chat.Data.ReviewPublicPassword, as: PublicPasswordData
  alias Chat.Data.ReviewWriteToken, as: TokenData
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias Chat.Data.VouchToken, as: VouchTokenData
  alias Chat.Pq.WriteGate
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

        %Operation{operation: :update, data: data} ->
          data["author_hash"] || review_author_hash(data["review_hash"])
      end

    with %{sign_pkey: sign_pkey} <- UserData.get_card(author_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  defp review_author_hash(review_hash) do
    case ReviewData.get_review(review_hash) do
      %{author_hash: ah} -> ah
      _ -> nil
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

  # --- Review gate (check phase) ---

  def check_review_gate(%Operation{operation: :insert, changes: changes}, pop_context) do
    origin_hash = changes["origin_hash"] || changes[:origin_hash]
    author_hash = changes["author_hash"] || changes[:author_hash]

    with :ok <- check_origin_access(origin_hash, author_hash) do
      check_token_nonce(pop_context, author_hash, origin_hash)
    end
  end

  def check_review_gate(%Operation{operation: :update}, _pop_context), do: :ok

  defp check_origin_access(origin_hash, author_hash) do
    case OriginSetting.get_review_access(origin_hash) do
      "open" ->
        :ok

      "invite_only" ->
        scope = "origins.#{origin_hash}.reviews.write"

        if author_hash == origin_hash or invited_to_write?(origin_hash, author_hash, scope),
          do: :ok,
          else: {:error, "not invited"}

      _ ->
        {:error, "not invited"}
    end
  end

  defp check_token_nonce(%{nonce: nonce}, author_hash, origin_hash) when is_binary(nonce) do
    case TokenData.get_review_write_token(nonce) do
      %ReviewWriteToken{
        deleted_flag: false,
        user_hash: ^author_hash,
        origin_hash: ^origin_hash,
        review_hash: nil
      } ->
        :ok

      %ReviewWriteToken{review_hash: rh} when not is_nil(rh) ->
        {:error, "token already used"}

      %ReviewWriteToken{deleted_flag: true} ->
        {:error, "token expired"}

      nil ->
        {:error, "token not found"}

      _ ->
        {:error, "token mismatch"}
    end
  end

  defp check_token_nonce(_pop_context, _author_hash, _origin_hash), do: :ok

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
        Versioning.check_insert_versioning(changeset)

      {:update, true} ->
        case Ecto.Changeset.apply_action(changeset, :update) do
          {:ok, new_review} ->
            changeset
            |> validate_edit_allowed(changeset.data)
            |> check_review_update_versioning(changeset.data, new_review)

          _ ->
            changeset
        end

      _ ->
        changeset
    end
  end

  defp invited_to_write?(origin_hash, author_hash, scope) do
    VouchTokenData.scoped_vouch_exists?(author_hash, scope) and
      match?(
        {:ok, _},
        VouchTokenData.chain_distance(origin_hash, author_hash, scope, WriteGate.max_depth())
      )
  end

  defp check_review_update_versioning(%{valid?: false} = changeset, _existing, _new_review),
    do: changeset

  defp check_review_update_versioning(changeset, existing, new_review) do
    cond do
      new_review.owner_timestamp <= existing.owner_timestamp ->
        Ecto.Changeset.add_error(changeset, :owner_timestamp, "timestamp not newer")

      new_review.parent_sign_hash != existing.sign_hash ->
        Ecto.Changeset.add_error(changeset, :parent_sign_hash, "does not match current version")

      true ->
        changeset
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

  def review_pre_apply_versioning(multi, changeset, context) do
    Versioning.pre_apply_versioning(multi, changeset, context)
  end

  def link_token_if_nonce(multi, changeset, %{nonce: nonce}) when is_binary(nonce) do
    import Ecto.Query

    review_hash = Ecto.Changeset.get_field(changeset, :review_hash)

    Ecto.Multi.run(multi, :link_review_token, fn repo, _changes ->
      {count, _} =
        from(rwt in ReviewWriteToken,
          where: rwt.nonce == ^nonce and is_nil(rwt.review_hash)
        )
        |> repo.update_all(set: [review_hash: review_hash])

      {:ok, count}
    end)
  end

  def link_token_if_nonce(multi, _changeset, _pop_context), do: multi

  # --- Shared helpers ---

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
