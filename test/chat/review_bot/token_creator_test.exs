defmodule Chat.ReviewBot.TokenCreatorTest do
  use ExUnit.Case, async: true
  import Rewire

  @fake_bot_hash "u_" <> String.duplicate("cd", 64)

  defmodule WorkerOk do
    @origin_hash "u_" <> String.duplicate("ab", 64)
    @bot_hash "u_" <> String.duplicate("cd", 64)

    def running?(_), do: true
    def info(_), do: %{bot_hash: @bot_hash, origin_hash: @origin_hash}
    def sign(_, _), do: :crypto.strong_rand_bytes(100)
    def ingest(_, _), do: {:ok, 1, []}
  end

  defmodule WorkerNotRunning do
    def running?(_), do: false
  end

  defmodule LiveVouch do
    def get_vouch_token(_kind, _issuer, _subject), do: %{deleted_flag: false}
  end

  defmodule NoVouch do
    def get_vouch_token(_kind, _issuer, _subject), do: nil
  end

  defmodule DeletedVouch do
    def get_vouch_token(_kind, _issuer, _subject), do: %{deleted_flag: true}
  end

  describe "create/2" do
    test "creates order-linked token and returns nonce" do
      creator = rewire(Chat.ReviewBot.TokenCreator, Worker: WorkerOk, VouchToken: LiveVouch)
      order_hash = "org_ord_" <> String.duplicate("ef", 64)

      assert {:ok, nonce} = creator.create(@fake_bot_hash, order_hash)
      assert is_binary(nonce)
      assert byte_size(nonce) == 32
    end

    test "creates reusable token (nil origin_order_hash)" do
      creator = rewire(Chat.ReviewBot.TokenCreator, Worker: WorkerOk, VouchToken: LiveVouch)

      assert {:ok, nonce} = creator.create(@fake_bot_hash)
      assert is_binary(nonce)
      assert byte_size(nonce) == 32
    end

    test "nonce is URL-safe base64 encoding of 24 random bytes" do
      creator = rewire(Chat.ReviewBot.TokenCreator, Worker: WorkerOk, VouchToken: LiveVouch)

      {:ok, nonce} = creator.create(@fake_bot_hash)

      assert {:ok, decoded} = Base.url_decode64(nonce, padding: false)
      assert byte_size(decoded) == 24
    end

    test "each call generates a unique nonce" do
      creator = rewire(Chat.ReviewBot.TokenCreator, Worker: WorkerOk, VouchToken: LiveVouch)

      {:ok, nonce1} = creator.create(@fake_bot_hash)
      {:ok, nonce2} = creator.create(@fake_bot_hash)

      assert nonce1 != nonce2
    end

    test "returns error when bot is not running" do
      creator =
        rewire(Chat.ReviewBot.TokenCreator, Worker: WorkerNotRunning, VouchToken: LiveVouch)

      assert {:error, :bot_not_running} = creator.create("u_nonexistent")
    end

    test "returns error when no vouch exists" do
      creator = rewire(Chat.ReviewBot.TokenCreator, Worker: WorkerOk, VouchToken: NoVouch)

      assert {:error, :no_live_vouch} = creator.create(@fake_bot_hash)
    end

    test "returns error when vouch is deleted" do
      creator = rewire(Chat.ReviewBot.TokenCreator, Worker: WorkerOk, VouchToken: DeletedVouch)

      assert {:error, :no_live_vouch} = creator.create(@fake_bot_hash)
    end
  end
end
