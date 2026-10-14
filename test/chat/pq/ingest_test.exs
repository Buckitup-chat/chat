defmodule Chat.Pq.IngestTest do
  use ChatWeb.DataCase, async: true

  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.User, as: UserData
  alias Chat.Pq.Ingest

  setup do
    identity = UserData.generate_pq_identity("TestBot")
    card = UserData.extract_pq_card(identity)
    %{identity: identity, card: card}
  end

  describe "apply/2 with self_pop" do
    test "ingests a user_card through the core pipeline", %{identity: identity, card: card} do
      pop_ctx = Ingest.self_pop(identity.sign_skey)

      mutations = [
        %{
          "type" => "insert",
          "modified" => user_card_modified(card),
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]

      assert {:ok, txid, _changes} = Ingest.apply(mutations, pop_ctx)
      assert is_integer(txid)
      assert Repo.get(UserCard, card.user_hash)
    end

    test "rejects a mutation with wrong PoP", %{card: card} do
      other = UserData.generate_pq_identity("Other")
      pop_ctx = Ingest.self_pop(other.sign_skey)

      mutations = [
        %{
          "type" => "insert",
          "modified" => user_card_modified(card),
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]

      assert {:error, _, _, _} = Ingest.apply(mutations, pop_ctx)
    end
  end

  describe "self_pop/1" do
    test "produces a valid PoP context", %{identity: identity} do
      ctx = Ingest.self_pop(identity.sign_skey)
      assert %{challenge: challenge, signature: signature} = ctx
      assert is_binary(challenge)
      assert is_binary(signature)
    end
  end

  defp user_card_modified(card) do
    %{
      "user_hash" => card.user_hash,
      "sign_pkey" => card.sign_pkey,
      "contact_pkey" => card.contact_pkey,
      "contact_cert" => card.contact_cert,
      "crypt_pkey" => card.crypt_pkey,
      "crypt_cert" => card.crypt_cert,
      "name" => card.name,
      "deleted_flag" => card.deleted_flag,
      "owner_timestamp" => card.owner_timestamp,
      "sign_b64" => card.sign_b64
    }
  end
end
