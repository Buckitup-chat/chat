defmodule Chat.Data.ShapesIntegrityTest do
  use ChatWeb.DataCase, async: true, group: :ets_deferred

  alias Chat.Data.Integrity
  alias Chat.Data.Integrity.Signable
  alias Chat.Data.Schemas.File, as: FileSchema
  alias Chat.Data.Schemas.FileChunk
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Shapes
  alias Chat.Data.Types.FileId
  alias Chat.Data.Types.UserStorageSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  setup do
    :ets.delete_all_objects(:buckitup_deferred_records)
    :ok
  end

  describe "registry completeness" do
    test "every shape has an atom name resolvable via registry" do
      for shape_mod <- Shapes.all() do
        name = shape_mod.shape_name()
        assert is_atom(name)
        assert Shapes.by_name(name) == shape_mod
      end
    end

    test "signable_fields excludes sign_b64 and __meta__ for all shapes" do
      for struct <- all_shape_structs() do
        fields = Signable.signable_fields(struct)

        refute Map.has_key?(fields, :sign_b64),
               "#{inspect(struct.__struct__)} must exclude :sign_b64"

        refute Map.has_key?(fields, :__meta__),
               "#{inspect(struct.__struct__)} must exclude :__meta__"
      end
    end

    defp all_shape_structs do
      identity = User.generate_pq_identity("Registry")
      card = signed_user_card(identity)

      [
        card,
        build_user_storage(card.user_hash),
        build_file(card.user_hash),
        build_file_chunk(card.user_hash, FileId.generate(), 0)
      ]
    end
  end

  describe "signature tampering — peer sync" do
    setup do
      identity = User.generate_pq_identity("Alice")
      card = insert_signed_user_card(identity)
      {:ok, identity: identity, user_hash: card.user_hash}
    end

    test "tampered user_card is not persisted" do
      other = User.generate_pq_identity("Tampered")
      card = signed_user_card(other)

      {:ok, _} = ShapeWriter.write(:user_card, :insert, %{card | name: "EVIL"})

      assert Repo.get(UserCard, card.user_hash) == nil
    end

    test "tampered user_storage is not persisted", %{identity: identity, user_hash: user_hash} do
      storage = signed_user_storage(identity, user_hash)

      {:ok, _} = ShapeWriter.write(:user_storage, :insert, %{storage | value_b64: "dGFtcGVyZWQ="})

      assert Repo.get_by(UserStorage, user_hash: user_hash, uuid: storage.uuid) == nil
    end

    test "tampered file is not persisted", %{identity: identity, user_hash: user_hash} do
      file = signed_file(identity, user_hash)

      {:ok, _} = ShapeWriter.write(:file, :insert, %{file | total_size: 999_999})

      assert Repo.get(FileSchema, file.file_id) == nil
    end

    test "tampered file_chunk is not persisted", %{identity: identity, user_hash: user_hash} do
      file = insert_signed_file(identity, user_hash)
      chunk = signed_file_chunk(identity, user_hash, file.file_id, 0)

      {:ok, _} = ShapeWriter.write(:file_chunk, :insert, %{chunk | size: 1})

      assert Repo.get_by(FileChunk, file_id: file.file_id, chunk_index: 0) == nil
    end
  end

  describe "wrong signing key — peer sync" do
    setup do
      alice = User.generate_pq_identity("Alice")
      card = insert_signed_user_card(alice)
      eve = User.generate_pq_identity("Eve")
      {:ok, alice: alice, eve: eve, user_hash: card.user_hash}
    end

    test "user_card signed by wrong key is not persisted" do
      eve = User.generate_pq_identity("Eve")
      wrong_signer = User.generate_pq_identity("Wrong")
      bad_card = eve |> User.extract_pq_card() |> sign_with_key(wrong_signer.sign_skey)

      {:ok, _} = ShapeWriter.write(:user_card, :insert, bad_card)

      assert Repo.get(UserCard, bad_card.user_hash) == nil
    end

    test "user_storage signed by wrong key is not persisted", %{eve: eve, user_hash: user_hash} do
      bad_storage = user_hash |> build_user_storage() |> sign_with_key(eve.sign_skey)

      {:ok, _} = ShapeWriter.write(:user_storage, :insert, bad_storage)

      assert Repo.get_by(UserStorage, user_hash: user_hash, uuid: bad_storage.uuid) == nil
    end

    test "file signed by wrong key is not persisted", %{eve: eve, user_hash: user_hash} do
      bad_file = user_hash |> build_file() |> sign_with_key(eve.sign_skey)

      {:ok, _} = ShapeWriter.write(:file, :insert, bad_file)

      assert Repo.get(FileSchema, bad_file.file_id) == nil
    end

    test "file_chunk signed by wrong key is not persisted", %{
      alice: alice,
      eve: eve,
      user_hash: user_hash
    } do
      file = insert_signed_file(alice, user_hash)
      bad_chunk = build_file_chunk(user_hash, file.file_id, 0) |> sign_with_key(eve.sign_skey)

      {:ok, _} = ShapeWriter.write(:file_chunk, :insert, bad_chunk)

      assert Repo.get_by(FileChunk, file_id: file.file_id, chunk_index: 0) == nil
    end
  end

  describe "valid signatures — peer sync baseline" do
    setup do
      identity = User.generate_pq_identity("Alice")
      card = insert_signed_user_card(identity)
      {:ok, identity: identity, card: card, user_hash: card.user_hash}
    end

    test "valid user_card is persisted", %{card: card} do
      assert Repo.get(UserCard, card.user_hash) != nil
    end

    test "valid user_storage is persisted", %{identity: identity, user_hash: user_hash} do
      storage = signed_user_storage(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:user_storage, :insert, storage)

      assert Repo.get_by(UserStorage, user_hash: user_hash, uuid: storage.uuid) != nil
    end

    test "valid file is persisted", %{identity: identity, user_hash: user_hash} do
      file = signed_file(identity, user_hash)
      {:ok, _} = ShapeWriter.write(:file, :insert, file)

      assert Repo.get(FileSchema, file.file_id) != nil
    end

    test "valid file_chunk is persisted", %{identity: identity, user_hash: user_hash} do
      file = insert_signed_file(identity, user_hash)
      chunk = signed_file_chunk(identity, user_hash, file.file_id, 0)
      {:ok, _} = ShapeWriter.write(:file_chunk, :insert, chunk)

      assert Repo.get_by(FileChunk, file_id: file.file_id, chunk_index: 0) != nil
    end
  end

  # --- Helpers ---

  defp sign_with_key(struct, sign_skey) do
    sign_b64 = struct |> Integrity.signature_payload() |> EnigmaPq.sign(sign_skey)
    signed = %{struct | sign_b64: sign_b64}

    case struct do
      %UserStorage{} ->
        sign_hash = sign_b64 |> EnigmaPq.hash() |> UserStorageSignHash.from_binary()
        %{signed | sign_hash: sign_hash}

      _ ->
        signed
    end
  end

  defp signed_user_card(identity, attrs \\ %{}) do
    identity |> User.extract_pq_card() |> struct(attrs) |> sign_with_key(identity.sign_skey)
  end

  defp insert_signed_user_card(identity, attrs \\ %{}) do
    card = signed_user_card(identity, attrs)
    {:ok, _} = ShapeWriter.write(:user_card, :insert, card)
    card
  end

  defp build_user_storage(user_hash, attrs \\ %{}) do
    %UserStorage{
      user_hash: user_hash,
      uuid: Ecto.UUID.generate(),
      value_b64: "dmFsdWU=",
      deleted_flag: false,
      owner_timestamp: System.os_time(:millisecond)
    }
    |> struct(attrs)
  end

  defp signed_user_storage(identity, user_hash, attrs \\ %{}) do
    user_hash |> build_user_storage(attrs) |> sign_with_key(identity.sign_skey)
  end

  defp build_file(user_hash, attrs \\ %{}) do
    chunk_sign_hash = :crypto.strong_rand_bytes(100) |> EnigmaPq.hash()

    %FileSchema{
      file_id: FileId.generate(),
      uploader_hash: user_hash,
      total_size: 4_194_304,
      chunk_size: 4_194_304,
      chunk_count: 1,
      chunk_sign_hashes: [chunk_sign_hash],
      owner_timestamp: System.os_time(:millisecond),
      deleted_flag: false
    }
    |> struct(attrs)
  end

  defp signed_file(identity, user_hash, attrs \\ %{}) do
    user_hash |> build_file(attrs) |> sign_with_key(identity.sign_skey)
  end

  defp insert_signed_file(identity, user_hash, attrs \\ %{}) do
    file = signed_file(identity, user_hash, attrs)
    {:ok, _} = ShapeWriter.write(:file, :insert, file)
    file
  end

  defp build_file_chunk(user_hash, file_id, index) do
    raw_data = :crypto.strong_rand_bytes(100)
    data_hash = raw_data |> EnigmaPq.hash() |> Chat.Data.Types.FileChunkDataHash.from_binary()

    %FileChunk{
      file_id: file_id,
      chunk_index: index,
      cid: cidv1_raw(raw_data),
      data_hash: data_hash,
      size: byte_size(raw_data),
      uploader_hash: user_hash,
      owner_timestamp: System.os_time(:millisecond)
    }
  end

  defp cidv1_raw(data) do
    digest = :crypto.hash(:sha256, data)
    "b" <> Base.encode32(<<1, 0x55, 0x12, 0x20>> <> digest, case: :lower, padding: false)
  end

  defp signed_file_chunk(identity, user_hash, file_id, index) do
    build_file_chunk(user_hash, file_id, index) |> sign_with_key(identity.sign_skey)
  end
end
