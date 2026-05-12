defmodule Chat.Data.File.Validation do
  @moduledoc "Signature and integrity validation for file storage operations."

  alias Chat.Data.File, as: FileData
  alias Chat.Data.Schemas.File
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.User, as: UserData
  alias Chat.Data.User.Validation, as: UserValidation
  alias Chat.TimeKeeper
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  import Chat.Db, only: [repo: 0]
  import Ecto.Query

  # --- Files (manifest) ---

  def file_allowed(operation, %{challenge: challenge, signature: signature}) do
    uploader_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["uploader_hash"] || changes[:uploader_hash]

        %Operation{operation: :update, data: %{"uploader_hash" => hash}} ->
          hash
      end

    card = UserData.get_card(uploader_hash)
    true = EnigmaPq.verify(challenge, signature, card.sign_pkey)
    :ok
  rescue
    _ -> {:error, "Invalid operation"}
  end

  def file_validate(file, changes, op) do
    case op do
      :insert ->
        file
        |> File.create_changeset(changes)
        |> UserValidation.validate_signature()

      :update ->
        file
        |> File.delete_changeset(changes)
        |> UserValidation.validate_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
    end
  end

  def file_pre_apply_insert(multi, changeset, _context) do
    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, file} ->
        multi
        |> Ecto.Multi.run(:verify_chunks, fn _repo, _changes ->
          verify_file_chunks(file)
        end)
        |> Ecto.Multi.run(:cleanup_upload_chunks, fn _repo, _changes ->
          FileData.delete_upload_chunks_for_file(file.file_id)
          {:ok, :cleaned}
        end)

      _ ->
        multi
    end
  end

  def file_pre_apply_update(multi, _changeset, _context), do: multi

  def validate_file_insert(file_struct) do
    %File{}
    |> File.create_changeset(Map.from_struct(file_struct))
    |> UserValidation.validate_signature()
  end

  def validate_file_update(existing, file_struct) do
    attrs =
      file_struct
      |> Map.from_struct()
      |> Map.take([:deleted_flag, :chunk_sign_hashes, :owner_timestamp, :sign_b64])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    existing
    |> File.delete_changeset(attrs)
    |> UserValidation.validate_signature()
    |> UserValidation.validate_timestamp_newer_than_existing()
  end

  # --- FileChunks ---

  def file_chunk_allowed(operation, %{challenge: challenge, signature: signature}) do
    %Operation{operation: :insert, changes: changes} = operation

    uploader_hash = changes["uploader_hash"] || changes[:uploader_hash]
    card = UserData.get_card(uploader_hash)
    true = EnigmaPq.verify(challenge, signature, card.sign_pkey)
    :ok
  rescue
    _ -> {:error, "Invalid operation"}
  end

  def file_chunk_validate(chunk, changes, :insert) do
    chunk
    |> FileChunk.create_changeset(changes)
    |> UserValidation.validate_signature()
  end

  def file_chunk_pre_apply_insert(multi, changeset, _context) do
    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, chunk} ->
        Ecto.Multi.run(multi, :upload_chunk_bookkeeping, fn _repo, _changes ->
          chunk_sign_hash = EnigmaPq.hash(chunk.sign_b64)

          FileData.insert_upload_chunk(%{
            file_id: chunk.file_id,
            chunk_index: chunk.chunk_index,
            chunk_sign_hash: chunk_sign_hash,
            uploader_hash: chunk.uploader_hash,
            size: chunk.size,
            updated_at: TimeKeeper.now_unix()
          })
        end)

      _ ->
        multi
    end
  end

  def validate_file_chunk_insert(chunk_struct) do
    %FileChunk{}
    |> FileChunk.create_changeset(Map.from_struct(chunk_struct))
    |> UserValidation.validate_signature()
  end

  # --- Private ---

  defp verify_file_chunks(file) do
    chunks =
      from(c in FileChunk,
        where: c.file_id == ^file.file_id,
        select: {c.chunk_index, c.sign_b64}
      )
      |> repo().all()
      |> Map.new()

    with {:chunk_count, true} <- {:chunk_count, map_size(chunks) == file.chunk_count},
         {:hashes, true} <- {:hashes, verify_chunk_hashes(file, chunks)} do
      {:ok, :verified}
    else
      {:chunk_count, false} ->
        {:error, :incomplete_chunks}

      {:hashes, false} ->
        {:error, :chunk_hash_mismatch}
    end
  end

  defp verify_chunk_hashes(file, chunks) do
    file.chunk_sign_hashes
    |> Enum.with_index()
    |> Enum.all?(fn {expected_hash, index} ->
      case Map.get(chunks, index) do
        nil -> false
        sign_b64 -> EnigmaPq.hash(sign_b64) == expected_hash
      end
    end)
  end
end
