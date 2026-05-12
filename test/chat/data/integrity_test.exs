defmodule Chat.Data.IntegrityTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.File, as: FileSchema

  describe "signature_payload/1 with list fields" do
    test "includes chunk_sign_hashes as concatenated base64 in payload" do
      hash_a = :crypto.strong_rand_bytes(64)
      hash_b = :crypto.strong_rand_bytes(64)

      file = build_file(chunk_sign_hashes: [hash_a, hash_b], chunk_count: 2)
      payload = Integrity.signature_payload(file)

      assert String.contains?(payload, Base.encode64(hash_a))
      assert String.contains?(payload, Base.encode64(hash_b))
    end

    test "empty chunk_sign_hashes produces shorter payload" do
      file_empty = build_file(chunk_sign_hashes: [], chunk_count: 0)
      file_one = build_file(chunk_sign_hashes: [:crypto.strong_rand_bytes(64)], chunk_count: 1)

      assert byte_size(Integrity.signature_payload(file_empty)) <
               byte_size(Integrity.signature_payload(file_one))
    end

    test "payload is deterministic" do
      file = build_file(chunk_sign_hashes: [:crypto.strong_rand_bytes(64)])

      assert Integrity.signature_payload(file) == Integrity.signature_payload(file)
    end
  end

  defp build_file(overrides) do
    defaults = [
      file_id: "f_00000000000000000000000000000001",
      uploader_hash: "u_" <> String.duplicate("a0", 64),
      total_size: 4_194_304,
      chunk_size: 4_194_304,
      chunk_count: 1,
      chunk_sign_hashes: [],
      owner_timestamp: 1_000_000,
      deleted_flag: false
    ]

    struct(FileSchema, Keyword.merge(defaults, overrides))
  end
end
