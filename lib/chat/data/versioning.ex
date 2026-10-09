defmodule Chat.Data.Versioning do
  @moduledoc """
  Shared versioning macro for entities with version history.

  Generates timestamp-based conflict resolution with version archiving.

  ## Usage

      use Chat.Data.Versioning,
        main_schema: DialogMessage,
        version_schema: DialogMessageVersion,
        main_conflict_target: :message_id,
        version_conflict_target: [:message_id, :sign_hash],
        fields: [:message_id, :dialog_hash, ...],
        mutable_fields: [:content_b64, :deleted_flag, ...]

  ## Generated functions

  Core (peer sync path):
    - `handle_insert_with_conflict/3`
    - `handle_update_with_versioning/3`
    - `archive_multi_insert/3`
    - `archive_changeset/1`

  Validation helpers (HTTP ingestion path):
    - `fetch_existing/2`
    - `check_insert_versioning/1`
    - `check_update_versioning/1`
    - `pre_apply_versioning/3`
  """

  def compare_timestamps(changeset, existing, new_record) do
    if new_record.owner_timestamp > existing.owner_timestamp do
      Ecto.Changeset.put_change(changeset, :parent_sign_hash, existing.sign_hash)
    else
      Ecto.Changeset.add_error(changeset, :owner_timestamp, "timestamp not newer")
    end
  end

  def timestamp_not_newer?(changeset) do
    Keyword.has_key?(changeset.errors, :owner_timestamp)
  end

  defmacro __using__(opts) do
    main_schema = Keyword.fetch!(opts, :main_schema)
    version_schema = Keyword.fetch!(opts, :version_schema)
    main_conflict_target = Keyword.fetch!(opts, :main_conflict_target)
    version_conflict_target = Keyword.fetch!(opts, :version_conflict_target)
    fields = Keyword.fetch!(opts, :fields)
    mutable_fields = Keyword.fetch!(opts, :mutable_fields)

    set_ast =
      for field <- mutable_fields do
        {field, quote(do: fragment(unquote("EXCLUDED.#{field}")))}
      end

    fetch_body =
      if is_atom(main_conflict_target) do
        quote do
          Chat.Db.repo().get(unquote(main_schema), Map.get(record, unquote(main_conflict_target)))
        end
      else
        quote do
          clauses =
            Enum.map(unquote(main_conflict_target), fn key -> {key, Map.get(record, key)} end)

          Chat.Db.repo().get_by(unquote(main_schema), clauses)
        end
      end

    quote do
      import Ecto.Query
      alias Ecto.Multi

      @dialyzer {:no_opaque, archive_and_insert: 3, archive_and_update: 3}

      @versioning_fields unquote(fields)
      @versioning_mutable_fields unquote(mutable_fields)

      def handle_insert_with_conflict(repo, existing, new_record) do
        if new_record.owner_timestamp > existing.owner_timestamp do
          archive_and_insert(repo, existing, new_record)
        else
          archive_changeset(new_record)
          |> repo.insert(
            on_conflict: :nothing,
            conflict_target: unquote(version_conflict_target)
          )
        end
      end

      def handle_update_with_versioning(repo, existing, new_record) do
        if new_record.owner_timestamp > existing.owner_timestamp do
          archive_and_update(repo, existing, new_record)
        else
          archive_changeset(new_record)
          |> repo.insert(
            on_conflict: :nothing,
            conflict_target: unquote(version_conflict_target)
          )
        end
      end

      defp archive_and_insert(repo, existing, new_record) do
        attrs =
          new_record
          |> Map.from_struct()
          |> Map.take(@versioning_fields)
          |> Map.put(:parent_sign_hash, existing.sign_hash)

        Multi.new()
        |> archive_multi_insert(:archive, existing)
        |> Multi.insert(
          :update_main,
          unquote(main_schema).create_changeset(struct(unquote(main_schema)), attrs),
          on_conflict: versioning_upsert_query(),
          conflict_target: unquote(main_conflict_target),
          allow_stale: true
        )
        |> repo.transaction()
        |> case do
          {:ok, %{update_main: result}} -> {:ok, result}
          {:error, _step, reason, _changes} -> {:error, reason}
        end
      end

      defp archive_and_update(repo, existing, new_record) do
        attrs =
          new_record
          |> Map.from_struct()
          |> Map.take(@versioning_mutable_fields)
          |> Map.put(:parent_sign_hash, existing.sign_hash)

        Multi.new()
        |> archive_multi_insert(:archive, existing)
        |> Multi.update(
          :update_main,
          unquote(main_schema).update_changeset(existing, attrs)
        )
        |> repo.transaction()
        |> case do
          {:ok, %{update_main: result}} -> {:ok, result}
          {:error, _step, reason, _changes} -> {:error, reason}
        end
      end

      defp versioning_upsert_query do
        from(m in unquote(main_schema),
          update: [
            set: unquote(set_ast)
          ],
          where:
            is_nil(m.owner_timestamp) or
              m.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
        )
      end

      def archive_multi_insert(multi, name, record) do
        Multi.insert(multi, name, archive_changeset(record),
          on_conflict: :nothing,
          conflict_target: unquote(version_conflict_target),
          allow_stale: true
        )
      end

      def archive_changeset(record) do
        record
        |> Map.from_struct()
        |> Map.take(@versioning_fields)
        |> then(&unquote(version_schema).changeset(struct(unquote(version_schema)), &1))
      end

      # --- Validation helpers (HTTP ingestion path) ---

      def fetch_existing(%{action: :update, data: data}, _record), do: data
      def fetch_existing(_, record), do: unquote(fetch_body)

      def check_insert_versioning(changeset) do
        with {:ok, record} <- Ecto.Changeset.apply_action(changeset, :insert),
             existing when not is_nil(existing) <- fetch_existing(nil, record) do
          Chat.Data.Versioning.compare_timestamps(changeset, existing, record)
        else
          _ -> changeset
        end
      end

      def check_update_versioning(changeset) do
        case Ecto.Changeset.apply_action(changeset, :update) do
          {:ok, record} ->
            Chat.Data.Versioning.compare_timestamps(changeset, changeset.data, record)

          _ ->
            changeset
        end
      end

      def pre_apply_versioning(multi, changeset, _context) do
        cond do
          changeset.valid? ->
            versioning_archive_if_newer(multi, changeset)

          Chat.Data.Versioning.timestamp_not_newer?(changeset) ->
            versioning_archive_old(multi, changeset)

          true ->
            multi
        end
      end

      defp versioning_archive_if_newer(multi, changeset) do
        case Ecto.Changeset.apply_action(changeset, changeset.action || :insert) do
          {:ok, record} ->
            existing = fetch_existing(changeset, record)

            if existing && record.owner_timestamp > existing.owner_timestamp do
              archive_multi_insert(multi, :archive_existing, existing)
            else
              multi
            end

          _ ->
            multi
        end
      end

      defp versioning_archive_old(multi, changeset) do
        case Ecto.Changeset.apply_action(%{changeset | action: :insert}, :insert) do
          {:ok, record} ->
            archive_multi_insert(multi, :archive_old_version, record)

          _ ->
            multi
        end
      end
    end
  end
end
