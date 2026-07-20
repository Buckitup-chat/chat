defmodule Chat.Data.ReviewList.Validation do
  @moduledoc "Validation for review_list operations."

  alias Chat.Data.Origin, as: OriginData
  alias Chat.Data.Review, as: ReviewData
  alias Chat.Data.ReviewPublicPassword
  alias Chat.Data.ReviewPostRight
  alias Chat.Data.ReviewRevokeRight
  alias Chat.Data.Schemas.ReviewList
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  # --- Peer sync validation ---

  def validate_review_list_insert(rl_struct) do
    %ReviewList{}
    |> ReviewList.create_changeset(Map.from_struct(rl_struct))
    |> UserValidation.validate_signature()
    |> validate_moderation_proof(rl_struct)
  end

  def validate_review_list_update(existing, rl_struct) do
    attrs =
      rl_struct
      |> Map.from_struct()
      |> Map.take([
        :password_b64,
        :review_password_sign_hash,
        :post_right_sign_hash,
        :revoke_right_sign_hash,
        :deleted_flag,
        :owner_timestamp,
        :sign_b64,
        :sign_hash
      ])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> ReviewList.update_changeset(attrs)
    |> UserValidation.validate_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
    |> validate_moderation_proof_on_update(existing, rl_struct)
  end

  # --- HTTP ingestion ---

  def review_list_allowed(operation, %{challenge: challenge, signature: signature}) do
    user_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["user_hash"] || changes[:user_hash]

        %Operation{operation: :update, data: %{"user_hash" => hash}} ->
          hash
      end

    with %{sign_pkey: sign_pkey} <- UserData.get_card(user_hash),
         true <- EnigmaPq.verify(challenge, signature, sign_pkey) do
      :ok
    else
      _ -> {:error, "Invalid operation"}
    end
  end

  def review_list_validate(rl, changes, op) do
    case op do
      :insert ->
        rl
        |> ReviewList.create_changeset(changes)
        |> UserValidation.validate_signature()
        |> validate_moderation_proof_from_changes(changes)

      :update ->
        rl
        |> ReviewList.update_changeset(changes)
        |> UserValidation.validate_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
        |> validate_moderation_proof_fields(
          rl.review_hash,
          effective(changes, "review_password_sign_hash", rl.review_password_sign_hash),
          effective(changes, "post_right_sign_hash", rl.post_right_sign_hash),
          effective(changes, "revoke_right_sign_hash", rl.revoke_right_sign_hash)
        )
    end
  end

  # --- Moderation proof validation ---

  defp validate_moderation_proof(changeset, rl_struct) do
    validate_moderation_proof_fields(
      changeset,
      rl_struct.review_hash,
      rl_struct.review_password_sign_hash,
      rl_struct.post_right_sign_hash,
      rl_struct.revoke_right_sign_hash
    )
  end

  defp validate_moderation_proof_from_changes(changeset, changes) do
    validate_moderation_proof_fields(
      changeset,
      changes["review_hash"] || changes[:review_hash],
      changes["review_password_sign_hash"] || changes[:review_password_sign_hash],
      changes["post_right_sign_hash"] || changes[:post_right_sign_hash],
      changes["revoke_right_sign_hash"] || changes[:revoke_right_sign_hash]
    )
  end

  # The proof fields are covered by the author's signature, so an update that
  # rewrites them (e.g. filling in `review_password_sign_hash` after a pre-mode
  # approval — docs §401) must be re-validated against the origin's moderation
  # mode, using the effective post-merge value of each field.
  defp validate_moderation_proof_on_update(changeset, existing, rl_struct) do
    validate_moderation_proof_fields(
      changeset,
      existing.review_hash,
      rl_struct.review_password_sign_hash || existing.review_password_sign_hash,
      rl_struct.post_right_sign_hash || existing.post_right_sign_hash,
      rl_struct.revoke_right_sign_hash || existing.revoke_right_sign_hash
    )
  end

  defp validate_moderation_proof_fields(changeset, review_hash, pwd_sh, post_sh, revoke_sh) do
    with true <- changeset.valid?,
         %{origin_hash: origin_hash} <- ReviewData.get_review(review_hash),
         %{moderation_mode: mode} <- OriginData.get_origin(origin_hash) do
      verify_proof_by_mode(changeset, mode, review_hash, pwd_sh, post_sh, revoke_sh)
    else
      false ->
        # Changeset already invalid (bad signature / stale timestamp); leave as-is.
        changeset

      _ ->
        # Doc "Server validation on review_list ingest" step 1/4: a review_list
        # entry whose review (or origin) does not exist cannot prove it went
        # through the moderation pipeline — reject rather than silently accept.
        Ecto.Changeset.add_error(changeset, :review_hash, "review or origin not found")
    end
  end

  # Proof requirements per docs "Moderation proof requirements by mode": each
  # cell is either `required` (proof row must exist and its sign_hash must
  # match) or `null` (the field must be absent for this mode).
  defp verify_proof_by_mode(cs, :none, review_hash, pwd_sh, post_sh, revoke_sh) do
    cs
    |> require_password_proof(review_hash, pwd_sh)
    |> require_null(:post_right_sign_hash, post_sh)
    |> require_null(:revoke_right_sign_hash, revoke_sh)
  end

  defp verify_proof_by_mode(cs, :post, review_hash, pwd_sh, post_sh, revoke_sh) do
    cs
    |> require_password_proof(review_hash, pwd_sh)
    |> require_null(:post_right_sign_hash, post_sh)
    |> require_revoke_right_proof(review_hash, revoke_sh)
  end

  defp verify_proof_by_mode(cs, :pre, review_hash, pwd_sh, post_sh, revoke_sh) do
    cs
    |> require_null(:review_password_sign_hash, pwd_sh)
    |> require_post_right_proof(review_hash, post_sh)
    |> require_revoke_right_proof(review_hash, revoke_sh)
  end

  defp require_null(cs, _field, nil), do: cs

  defp require_null(cs, field, _value),
    do: Ecto.Changeset.add_error(cs, field, "must be null for this moderation mode")

  defp require_password_proof(cs, _review_hash, nil),
    do:
      Ecto.Changeset.add_error(
        cs,
        :review_password_sign_hash,
        "required for this moderation mode"
      )

  defp require_password_proof(cs, review_hash, sign_hash) do
    case ReviewPublicPassword.get_review_public_password(review_hash, sign_hash) do
      nil ->
        Ecto.Changeset.add_error(cs, :review_password_sign_hash, "referenced row does not exist")

      _ ->
        cs
    end
  end

  defp require_post_right_proof(cs, _review_hash, nil),
    do: Ecto.Changeset.add_error(cs, :post_right_sign_hash, "required for this moderation mode")

  defp require_post_right_proof(cs, review_hash, sign_hash) do
    if matches_sign_hash?(ReviewPostRight.get_post_right(review_hash), sign_hash),
      do: cs,
      else: Ecto.Changeset.add_error(cs, :post_right_sign_hash, "referenced row does not exist")
  end

  defp require_revoke_right_proof(cs, _review_hash, nil),
    do: Ecto.Changeset.add_error(cs, :revoke_right_sign_hash, "required for this moderation mode")

  defp require_revoke_right_proof(cs, review_hash, sign_hash) do
    if matches_sign_hash?(ReviewRevokeRight.get_revoke_right(review_hash), sign_hash),
      do: cs,
      else: Ecto.Changeset.add_error(cs, :revoke_right_sign_hash, "referenced row does not exist")
  end

  defp matches_sign_hash?(%{sign_hash: sign_hash}, sign_hash) when not is_nil(sign_hash), do: true
  defp matches_sign_hash?(_row, _sign_hash), do: false

  defp effective(changes, key, existing_value) do
    changes[key] || changes[String.to_existing_atom(key)] || existing_value
  end
end
