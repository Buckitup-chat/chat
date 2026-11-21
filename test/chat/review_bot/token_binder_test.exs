defmodule Chat.ReviewBot.TokenBinderTest do
  use ExUnit.Case, async: true
  import Rewire

  alias Chat.Data.Schemas.ReviewWriteToken
  alias Chat.Data.Types.ReviewWriteTokenNonceHash

  @bot_hash "u_bot"
  @origin_hash "u_origin"
  @reviewer_hash "u_reviewer"
  @nonce "test_nonce_abc"
  @nonce_hash ReviewWriteTokenNonceHash.from_nonce(@nonce)
  @pop %{challenge: "test_challenge", signature: "test_sig"}

  defmodule Tokens do
    def nonce_hash, do: ReviewWriteTokenNonceHash.from_nonce("test_nonce_abc")

    def lookup(nonce_hash, token_fun) do
      if nonce_hash == nonce_hash(), do: token_fun.()
    end

    def order_linked do
      %ReviewWriteToken{
        nonce_hash: nonce_hash(),
        nonce_enc_b64: "enc_test_nonce_abc",
        origin_hash: "u_origin",
        review_bot_hash: "u_bot",
        origin_order_hash: "org_ord_1",
        deleted_flag: false,
        owner_timestamp: 1000,
        sign_b64: "old_sig",
        sign_hash: "rwt_old"
      }
    end

    def reusable do
      %{order_linked() | origin_order_hash: nil}
    end
  end

  defmodule QueriesOrderLinked do
    def get_review_write_token(hash), do: Tokens.lookup(hash, &Tokens.order_linked/0)
    def get_card("u_reviewer"), do: %{sign_pkey: "pkey_reviewer"}
    def valid_card?(_), do: true
    def get_vouch_token(_, _, _), do: %{deleted_flag: false}
    def scoped_vouch_exists?(_, _), do: true
  end

  defmodule QueriesReusable do
    def get_review_write_token(hash), do: Tokens.lookup(hash, &Tokens.reusable/0)
    def get_card("u_reviewer"), do: %{sign_pkey: "pkey_reviewer"}
    def valid_card?(_), do: true
    def get_vouch_token(_, _, _), do: %{deleted_flag: false}
    def scoped_vouch_exists?(_, _), do: true
  end

  defmodule QueriesDeleted do
    def get_review_write_token(_), do: %ReviewWriteToken{deleted_flag: true}
  end

  defmodule QueriesNotFound do
    def get_review_write_token(_), do: nil
  end

  defmodule QueriesReviewerNotFound do
    def get_review_write_token(hash), do: Tokens.lookup(hash, &Tokens.order_linked/0)
    def get_card("u_reviewer"), do: nil
  end

  defmodule QueriesInvalidPop do
    def get_review_write_token(hash), do: Tokens.lookup(hash, &Tokens.order_linked/0)
    def get_card("u_reviewer"), do: %{sign_pkey: "pkey_reviewer"}
    def valid_card?(_), do: true
  end

  defmodule QueriesNoOriginVouch do
    def get_review_write_token(hash), do: Tokens.lookup(hash, &Tokens.order_linked/0)
    def get_card("u_reviewer"), do: %{sign_pkey: "pkey_reviewer"}
    def valid_card?(_), do: true
    def get_vouch_token(_, _, _), do: nil
  end

  defmodule QueriesNoDeviceVouch do
    def get_review_write_token(hash), do: Tokens.lookup(hash, &Tokens.order_linked/0)
    def get_card("u_reviewer"), do: %{sign_pkey: "pkey_reviewer"}
    def valid_card?(_), do: true
    def get_vouch_token(_, _, _), do: %{deleted_flag: false}
    def scoped_vouch_exists?(_, _), do: false
  end

  defmodule EnigmaOk do
    def verify(_, _, _), do: true
    def hash(data), do: :crypto.hash(:sha256, data)
  end

  defmodule EnigmaInvalid do
    def verify(_, _, _), do: false
  end

  defmodule WorkerOk do
    def running?("u_bot"), do: true
    def info("u_bot"), do: %{origin_hash: "u_origin"}
    def sign("u_bot", _payload), do: "test_signature_b64"
    def wrap_nonce("u_bot", nonce), do: "enc_" <> nonce

    def ingest("u_bot", mutations) do
      test_pid = Process.whereis(:binder_test)
      if test_pid, do: send(test_pid, {:ingested, mutations})
      {:ok, "txid_1", []}
    end
  end

  defmodule WorkerNotRunning do
    def running?("u_bot"), do: false
  end

  defmodule DeviceIdOk do
    def id, do: "test_device"
  end

  defmodule IntegrityOk do
    def signature_payload(_data), do: "payload_bytes"
  end

  defmodule TimeKeeperOk do
    def now_unix, do: 5000
  end

  rewire(Chat.ReviewBot.RowBuilder, Worker: WorkerOk, Integrity: IntegrityOk, as: RowBuilderOk)

  describe "bind/3 order-linked" do
    test "sets user_hash on existing token and creates vouches" do
      Process.register(self(), :binder_test)

      binder =
        rewire(Chat.ReviewBot.TokenBinder,
          BinderQueries: QueriesOrderLinked,
          EnigmaPq: EnigmaOk,
          Worker: WorkerOk,
          DeviceId: DeviceIdOk,
          Integrity: IntegrityOk,
          TimeKeeper: TimeKeeperOk,
          RowBuilder: RowBuilderOk
        )

      assert {:ok, @nonce} = binder.bind(@nonce, @reviewer_hash, @pop)
      assert_received {:ingested, mutations}

      vouch_mutations =
        Enum.filter(mutations, &(&1["syncMetadata"]["relation"] == "vouch_tokens"))

      token_mutations =
        Enum.filter(mutations, &(&1["syncMetadata"]["relation"] == "review_write_tokens"))

      assert length(vouch_mutations) == 5
      assert length(token_mutations) == 1

      [token_mut] = token_mutations
      assert token_mut["modified"]["nonce_hash"] == @nonce_hash
      assert token_mut["modified"]["nonce_enc_b64"] == "enc_" <> @nonce
      assert token_mut["modified"]["user_hash"] == @reviewer_hash
      assert token_mut["modified"]["sign_b64"] == "test_signature_b64"

      origin_vouches =
        Enum.filter(vouch_mutations, &String.starts_with?(&1["modified"]["kind"], "origins."))

      device_vouches =
        Enum.filter(vouch_mutations, &String.starts_with?(&1["modified"]["kind"], "device."))

      assert length(origin_vouches) == 1
      assert length(device_vouches) == 4

      [ov] = origin_vouches
      assert ov["modified"]["kind"] == "origins.#{@origin_hash}.reviews.write.#{@nonce_hash}"
      assert ov["modified"]["issuer_hash"] == @bot_hash
      assert ov["modified"]["subject_hash"] == @reviewer_hash

      device_kinds = device_vouches |> Enum.map(& &1["modified"]["kind"]) |> Enum.sort()

      assert device_kinds == [
               "device.test_device.storage.write.review",
               "device.test_device.storage.write.review_password_candidate",
               "device.test_device.storage.write.review_post_right_candidate",
               "device.test_device.storage.write.review_revoke_right_candidate"
             ]
    after
      Process.unregister(:binder_test)
    end
  end

  describe "bind/3 reusable" do
    test "creates new token with parent_nonce_hash, original stays untouched" do
      Process.register(self(), :binder_test)

      binder =
        rewire(Chat.ReviewBot.TokenBinder,
          BinderQueries: QueriesReusable,
          EnigmaPq: EnigmaOk,
          Worker: WorkerOk,
          DeviceId: DeviceIdOk,
          Integrity: IntegrityOk,
          TimeKeeper: TimeKeeperOk,
          RowBuilder: RowBuilderOk
        )

      assert {:ok, new_nonce} = binder.bind(@nonce, @reviewer_hash, @pop)
      assert new_nonce != @nonce

      assert_received {:ingested, mutations}

      token_mutations =
        Enum.filter(mutations, &(&1["syncMetadata"]["relation"] == "review_write_tokens"))

      assert length(token_mutations) == 1
      [token_mut] = token_mutations
      new_nonce_hash = ReviewWriteTokenNonceHash.from_nonce(new_nonce)
      assert token_mut["modified"]["nonce_hash"] == new_nonce_hash
      assert token_mut["modified"]["nonce_enc_b64"] == "enc_" <> new_nonce
      assert token_mut["modified"]["parent_nonce_hash"] == @nonce_hash

      [ov] =
        Enum.filter(mutations, &String.starts_with?(&1["modified"]["kind"] || "", "origins."))

      assert ov["modified"]["kind"] == "origins.#{@origin_hash}.reviews.write.#{new_nonce_hash}"
      assert token_mut["modified"]["user_hash"] == @reviewer_hash
      assert token_mut["modified"]["origin_order_hash"] == nil
    after
      Process.unregister(:binder_test)
    end
  end

  describe "bind/3 rejections" do
    test "rejects when token not found" do
      binder = rewire(Chat.ReviewBot.TokenBinder, BinderQueries: QueriesNotFound)
      assert {:error, :token_not_found} = binder.bind("missing", @reviewer_hash, @pop)
    end

    test "rejects when token is soft-deleted" do
      binder = rewire(Chat.ReviewBot.TokenBinder, BinderQueries: QueriesDeleted)
      assert {:error, :token_deleted} = binder.bind(@nonce, @reviewer_hash, @pop)
    end

    test "rejects when reviewer identity not found" do
      binder = rewire(Chat.ReviewBot.TokenBinder, BinderQueries: QueriesReviewerNotFound)
      assert {:error, :reviewer_not_found} = binder.bind(@nonce, @reviewer_hash, @pop)
    end

    test "rejects when PoP signature is invalid" do
      binder =
        rewire(Chat.ReviewBot.TokenBinder,
          BinderQueries: QueriesInvalidPop,
          EnigmaPq: EnigmaInvalid
        )

      assert {:error, :invalid_pop} = binder.bind(@nonce, @reviewer_hash, @pop)
    end

    test "rejects when bot is not running" do
      binder =
        rewire(Chat.ReviewBot.TokenBinder,
          BinderQueries: QueriesOrderLinked,
          EnigmaPq: EnigmaOk,
          Worker: WorkerNotRunning
        )

      assert {:error, :bot_not_running} = binder.bind(@nonce, @reviewer_hash, @pop)
    end

    test "rejects when bot lacks origin vouch" do
      binder =
        rewire(Chat.ReviewBot.TokenBinder,
          BinderQueries: QueriesNoOriginVouch,
          EnigmaPq: EnigmaOk,
          Worker: WorkerOk
        )

      assert {:error, :no_bot_origin_vouch} = binder.bind(@nonce, @reviewer_hash, @pop)
    end

    test "rejects when bot lacks device vouch" do
      binder =
        rewire(Chat.ReviewBot.TokenBinder,
          BinderQueries: QueriesNoDeviceVouch,
          EnigmaPq: EnigmaOk,
          Worker: WorkerOk,
          DeviceId: DeviceIdOk
        )

      assert {:error, :no_bot_device_vouch} = binder.bind(@nonce, @reviewer_hash, @pop)
    end
  end
end
