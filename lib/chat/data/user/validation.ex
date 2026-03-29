defmodule Chat.Data.User.Validation do
  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Versioning
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  import Chat.Db, only: [repo: 0]

  defprotocol TimestampedData do
    @moduledoc """
    Protocol for data structures that have owner timestamps.
    Used for validating that updates have newer timestamps.
    """

    @doc """
    Returns the existing timestamp from the data structure, or nil if not set.
    """
    def existing_timestamp(data)
  end

  def user_card_allowed(operation, %{challenge: challenge, signature: signature}) do
    sign_pkey =
      case operation do
        %Operation{operation: :insert} ->
          {:ok, sign_pkey} = operation_change(operation, "sign_pkey")
          sign_pkey

        %Operation{operation: :update, data: data} ->
          data["user_hash"]
          |> UserData.get_card()
          |> then(fn card -> card.sign_pkey end)
      end

    true = EnigmaPq.verify(challenge, signature, sign_pkey)
    :ok
  rescue
    _ -> {:error, "Invalid operation"}
  end

  def user_card_validate(card, changes, op) do
    case op do
      :insert ->
        card
        |> UserCard.create_changeset(changes)
        |> validate_signature()
        |> fail_invalid_user_card()

      :update ->
        cond do
          user_card_deleted_flag_change?(card, changes) ->
            card
            |> UserCard.update_deleted_flag_changeset(changes)
            |> validate_signature()
            |> validate_timestamp_newer_than_existing()

          true ->
            card
            |> UserCard.update_name_changeset(changes)
            |> validate_signature()
            |> validate_timestamp_newer_than_existing()
        end
    end
  end

  @doc """
  Validates and builds changeset for user_card insert from Electric sync.
  Returns changeset with signature verification.
  """
  def validate_user_card_insert(card_struct) do
    %UserCard{}
    |> UserCard.create_changeset(Map.from_struct(card_struct))
    |> validate_signature()
    |> fail_invalid_user_card()
  end

  @doc """
  Validates and builds changeset for user_card update from Electric sync.
  Returns changeset with signature and timestamp verification.
  """
  def validate_user_card_update(existing, card_struct) do
    attrs =
      card_struct
      |> Map.take([:name, :deleted_flag, :owner_timestamp, :sign_b64])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    if user_card_deleted_flag_change?(existing, attrs),
      do:
        existing
        |> UserCard.update_deleted_flag_changeset(attrs)
        |> validate_signature()
        |> validate_timestamp_newer_than_existing(),
      else:
        existing
        |> UserCard.update_name_changeset(attrs)
        |> validate_signature()
        |> validate_timestamp_newer_than_existing()
  end

  @doc """
  Validates and builds changeset for user_card delete from Electric sync.
  Returns changeset with signature and timestamp verification.
  """
  def validate_user_card_delete(existing, card_struct) do
    attrs =
      card_struct
      |> Map.take([:deleted_flag, :owner_timestamp, :sign_b64])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> UserCard.update_deleted_flag_changeset(attrs)
    |> validate_signature()
    |> validate_timestamp_newer_than_existing()
  end

  defp fail_invalid_user_card(changeset) do
    with true <- changeset.valid?,
         card_data <- Ecto.Changeset.apply_changes(changeset),
         false <- UserData.valid_card?(card_data) do
      Ecto.Changeset.add_error(changeset, :user_hash, "invalid_user_card_integrity")
    else
      _ -> changeset
    end
  end

  def user_storage_allowed(operation, %{challenge: challenge, signature: signature}) do
    user_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["user_hash"] || changes[:user_hash]

        %Operation{operation: :update, data: %{"user_hash" => hash}} ->
          hash

        %Operation{operation: :delete, data: %{"user_hash" => hash}} ->
          hash
      end

    card = UserData.get_card(user_hash)
    true = EnigmaPq.verify(challenge, signature, card.sign_pkey)
    :ok
  rescue
    _ -> {:error, "Invalid operation"}
  end

  def user_storage_validate(storage, changes, op) do
    case op do
      :insert ->
        storage
        |> UserStorage.create_changeset(changes)
        |> validate_signature()

      :update ->
        storage
        |> UserStorage.update_changeset(changes)
        |> validate_signature()
    end
  end

  @doc """
  Validation function for user_storage that integrates versioning logic.
  This is used by HTTP ingestion to handle versioning automatically.

  Returns an Ecto.Multi that includes both validation and versioning operations.
  """
  def user_storage_validate_with_versioning(storage, changes, op) do
    # First validate the changeset
    changeset = user_storage_validate(storage, changes, op)

    case {op, changeset.valid?} do
      {:insert, true} ->
        # For inserts, check if a conflict exists and handle versioning
        with {:ok, new_storage} <- Ecto.Changeset.apply_action(changeset, :insert),
             existing when not is_nil(existing) <-
               repo().get_by(UserStorage, user_hash: new_storage.user_hash, uuid: new_storage.uuid) do
          # Conflict exists - use versioning logic
          handle_insert_with_versioning(changeset, existing, new_storage)
        else
          _ -> changeset
        end

      {:update, true} ->
        # For updates, check timestamp and handle versioning
        with {:ok, new_storage} <- Ecto.Changeset.apply_action(changeset, :update),
             existing <- changeset.data do
          handle_update_with_versioning(changeset, existing, new_storage)
        else
          _ -> changeset
        end

      _ ->
        changeset
    end
  end

  defp handle_insert_with_versioning(changeset, existing, new_storage) do
    if new_storage.owner_timestamp > existing.owner_timestamp do
      # New version is newer - return changeset with on_conflict to replace
      # The existing will be archived in pre_apply
      Ecto.Changeset.put_change(changeset, :parent_sign_hash, existing.sign_hash)
    else
      # New version is older - mark changeset as ignored and archive new version
      %{changeset | action: :ignore}
    end
  end

  defp handle_update_with_versioning(changeset, existing, new_storage) do
    if new_storage.owner_timestamp > existing.owner_timestamp do
      # New version is newer - update with parent_sign_hash
      Ecto.Changeset.put_change(changeset, :parent_sign_hash, existing.sign_hash)
    else
      # New version is older - mark as ignored
      %{changeset | action: :ignore}
    end
  end

  @doc """
  Pre-apply callback for user_storage that handles versioning.
  Archives the existing version when a newer version is being inserted/updated.
  When an older version comes in, it archives the old version to the versions table.
  """
  def user_storage_pre_apply_versioning(multi, changeset, _context) do
    # Only proceed if changeset is valid and not marked as :ignore
    if changeset.valid? and changeset.action != :ignore do
      with {:ok, new_storage} <- Ecto.Changeset.apply_action(changeset, changeset.action || :insert) do
        # Get the existing record if it exists
        existing =
          case changeset.action do
            :update -> changeset.data
            _ -> repo().get_by(UserStorage, user_hash: new_storage.user_hash, uuid: new_storage.uuid)
          end

        if existing && new_storage.owner_timestamp > existing.owner_timestamp do
          # New version is newer - archive the existing version
          Ecto.Multi.insert(multi, :archive_existing, Versioning.archive_changeset(existing))
        else
          multi
        end
      else
        _ -> multi
      end
    else
      # If changeset is marked as :ignore (older version), archive the new version to versions table
      if changeset.action == :ignore do
        with {:ok, new_storage} <- Ecto.Changeset.apply_action(%{changeset | action: :insert}, :insert) do
          Ecto.Multi.insert(multi, :archive_old_version, Versioning.archive_changeset(new_storage))
        else
          _ -> multi
        end
      else
        multi
      end
    end
  end

  @doc """
  Validates and builds changeset for user_storage insert from Electric sync.
  Returns changeset with signature verification.
  """
  def validate_user_storage_insert(storage_struct) do
    %UserStorage{}
    |> UserStorage.create_changeset(Map.from_struct(storage_struct))
    |> validate_signature()
  end

  @doc """
  Validates and builds changeset for user_storage update from Electric sync.
  Returns changeset with signature verification.
  """
  def validate_user_storage_update(existing, storage_struct) do
    attrs =
      storage_struct
      |> Map.from_struct()
      |> Map.take([
        :value_b64,
        :deleted_flag,
        :parent_sign_hash,
        :owner_timestamp,
        :sign_b64,
        :sign_hash
      ])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> UserStorage.update_changeset(attrs)
    |> validate_signature()
  end

  defp operation_change(%Operation{changes: changes}, field) do
    case Map.get(changes, field) || Map.get(changes, String.to_existing_atom(field)) do
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, "Missing #{field} in mutation changes"}
    end
  end

  defp user_card_deleted_flag_change?(existing, changes) do
    deleted_flag = Map.get(changes, "deleted_flag") || Map.get(changes, :deleted_flag)
    change_name = Map.get(changes, "name") || Map.get(changes, :name)

    deleted_flag != nil and (is_nil(change_name) or change_name == Map.get(existing, :name))
  end

  @doc """
  Validates signature on a changeset by applying it and verifying with Integrity.verify_signature/1.
  Adds error to :sign_b64 field if signature is invalid.
  """
  def validate_signature(changeset) do
    with {:ok, data} <- Ecto.Changeset.apply_action(changeset, :validate),
         {:error, reason} <- Integrity.verify_signature(data) do
      Ecto.Changeset.add_error(changeset, :sign_b64, "invalid signature: #{reason}")
    else
      _ -> changeset
    end
  end

  @doc """
  Validates that the new timestamp in the changeset is newer than the existing timestamp.
  Uses a protocol to extract the timestamp field from the schema.
  Returns changeset with action: :ignore if timestamp is not newer.
  """
  def validate_timestamp_newer_than_existing(changeset) do
    with existing_timestamp when not is_nil(existing_timestamp) <-
           TimestampedData.existing_timestamp(changeset.data),
         new_timestamp when not is_nil(new_timestamp) <-
           Ecto.Changeset.get_change(changeset, :owner_timestamp),
         true <- new_timestamp <= existing_timestamp do
      %{changeset | valid?: false, action: :ignore}
    else
      _ -> changeset
    end
  end
end
