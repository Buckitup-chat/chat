defmodule Chat.Test.PgPair.Files do
  @moduledoc "File manifest / chunk / missing_chunk rows on a `PgPairCase` repo."

  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.MissingChunk
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Types.FileId

  @uploader_hash "u_" <> String.duplicate("cd", 64)
  @data_hash "fd_" <> String.duplicate("ab", 64)
  @ts 1_000_000

  def data_hash, do: @data_hash

  def new_file_id, do: FileId.generate()

  @doc "Uploader card, then the file manifest and its `chunk_count` chunk rows, in one transaction."
  def file!(repo, file_id, chunk_count) do
    repo.transaction(fn ->
      user_card!(repo)

      repo.insert_all("files", [
        %{
          file_id: file_id,
          uploader_hash: @uploader_hash,
          total_size: chunk_count * 4096,
          chunk_count: chunk_count,
          chunk_sign_hashes: List.duplicate("h", chunk_count),
          owner_timestamp: @ts,
          sign_b64: "sig"
        }
      ])

      Enum.each(0..(chunk_count - 1), &chunk!(repo, file_id, &1))
    end)

    file_id
  end

  def user_card!(repo) do
    %UserCard{
      user_hash: @uploader_hash,
      sign_pkey: "pkey",
      contact_pkey: "cpkey",
      contact_cert: "ccert",
      crypt_pkey: "crpkey",
      crypt_cert: "crcert",
      name: "uploader",
      deleted_flag: false,
      owner_timestamp: @ts,
      sign_b64: "sig"
    }
    |> repo.insert!(on_conflict: :nothing)
  end

  def chunk!(repo, file_id, chunk_index) do
    %FileChunk{
      file_id: file_id,
      chunk_index: chunk_index,
      data_hash: @data_hash,
      size: 4096,
      uploader_hash: @uploader_hash,
      owner_timestamp: @ts,
      sign_b64: "sig"
    }
    |> repo.insert!()
  end

  def missing!(repo, file_id, chunk_index, source_drive_id) do
    repo.insert_all(MissingChunk, [
      %{
        file_id: file_id,
        chunk_index: chunk_index,
        data_hash: @data_hash,
        size: 4096,
        peer_url: nil,
        source_drive_id: source_drive_id,
        attempts: 0,
        updated_at: @ts
      }
    ])
  end

  @doc "`%{chunk_index => source_drive_id}` of `file_id`'s missing_chunks on `repo`."
  def missing_sources(repo, file_id) do
    import Ecto.Query

    from(m in MissingChunk,
      where: m.file_id == ^file_id,
      select: {m.chunk_index, m.source_drive_id}
    )
    |> repo.all()
    |> Map.new()
  end
end
