defmodule Chat.Test.DialogDataFixtures do
  @moduledoc """
  Signed PQ dialog rows (`Chat.Data.Dialog`) for data-layer tests: dialog keys, messages,
  reactions and receipts, plus an Alice ↔ Bob dialog setup.
  """

  import Chat.Test.ReviewFixtures,
    only: [insert_user_card: 1, sign_with_hash: 3, sign_with_key: 2]

  alias Chat.Data.Schemas.DialogKey
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Schemas.DialogMessageReceipt
  alias Chat.Data.Types.DialogHash
  alias Chat.Data.Types.DialogMessageId
  alias Chat.Data.Types.DialogMessageReactionHash
  alias Chat.Data.Types.DialogMessageReceiptHash
  alias Chat.Data.Types.DialogMessageSignHash
  alias Chat.Data.User
  alias Chat.NetworkSynchronization.Electric.ShapeWriter

  @message_sign_hash "dms_" <> String.duplicate("cd", 64)

  @doc """
  Setup: clears deferred records, inserts signed user cards for Alice and Bob and returns
  `alice`, `bob`, `alice_hash`, `bob_hash` and their `dialog_hash`.
  """
  def alice_and_bob(_ctx) do
    :ets.delete_all_objects(:buckitup_deferred_records)

    alice = User.generate_pq_identity("Alice")
    bob = User.generate_pq_identity("Bob")
    alice_card = insert_user_card(alice)
    bob_card = insert_user_card(bob)

    [
      alice: alice,
      bob: bob,
      alice_hash: alice_card.user_hash,
      bob_hash: bob_card.user_hash,
      dialog_hash: DialogHash.for_pair(alice_card.user_hash, bob_card.user_hash)
    ]
  end

  @doc "Setup: both Alice and Bob publish their dialog key, making them participants."
  def join_dialog(ctx) do
    insert_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)
    insert_dialog_key(ctx.bob, ctx.dialog_hash, ctx.bob_hash, ctx.alice_hash)
    :ok
  end

  @doc "Alice publishes her dialog key and a message to Bob; returns the persisted message."
  def insert_alice_message(ctx) do
    insert_dialog_key(ctx.alice, ctx.dialog_hash, ctx.alice_hash, ctx.bob_hash)
    msg = signed_message(ctx.alice, ctx.dialog_hash, ctx.alice_hash)
    {:ok, _} = ShapeWriter.write(:dialog_messages, :insert, msg)
    msg
  end

  @doc "`DialogKey` from `sender_hash` to `peer_hash`, signed by `identity`. `attrs`: `:owner_timestamp`."
  def signed_dialog_key(identity, dialog_hash, sender_hash, peer_hash, attrs \\ []) do
    %DialogKey{
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      peer_hash: peer_hash,
      peer_kem_wrap_key_b64: :crypto.strong_rand_bytes(32),
      peer_wrapped_msg_key_b64: :crypto.strong_rand_bytes(44),
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, now()),
      deleted_flag: false
    }
    |> sign_with_key(identity.sign_skey)
  end

  @doc "Writes a signed `DialogKey` through `ShapeWriter` and returns it."
  def insert_dialog_key(identity, dialog_hash, sender_hash, peer_hash) do
    dk = signed_dialog_key(identity, dialog_hash, sender_hash, peer_hash)
    {:ok, _} = ShapeWriter.write(:dialog_keys, :insert, dk)
    dk
  end

  @doc """
  `DialogMessage` with random content and no refs, signed by `identity` (with `sign_hash`).
  `attrs`: `:message_id`, `:owner_timestamp`.
  """
  def signed_message(identity, dialog_hash, sender_hash, attrs \\ []) do
    %DialogMessage{
      message_id: Keyword.get(attrs, :message_id, DialogMessageId.generate()),
      dialog_hash: dialog_hash,
      sender_hash: sender_hash,
      content_b64: :crypto.strong_rand_bytes(32),
      deleted_flag: false,
      refs_map_b64: nil,
      parent_sign_hash: nil,
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, now())
    }
    |> sign_with_hash(identity.sign_skey, &DialogMessageSignHash.from_binary/1)
  end

  @doc """
  Unsigned `DialogMessageReaction` by `reactor_hash`. `attrs`: `:dialog_hash` (required),
  `:reaction_hash`, `:message_id`, `:deleted_flag`, `:owner_timestamp`.
  """
  def build_reaction(reactor_hash, attrs) do
    %DialogMessageReaction{
      reaction_hash: Keyword.get(attrs, :reaction_hash, generate_reaction_hash()),
      dialog_hash: Keyword.fetch!(attrs, :dialog_hash),
      message_id: Keyword.get(attrs, :message_id, DialogMessageId.generate()),
      message_sign_hash: @message_sign_hash,
      reactor_hash: reactor_hash,
      type_b64: :crypto.strong_rand_bytes(24),
      deleted_flag: Keyword.get(attrs, :deleted_flag, false),
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, now())
    }
  end

  @doc "`build_reaction/2` signed by `identity`."
  def signed_reaction(identity, reactor_hash, attrs) do
    reactor_hash
    |> build_reaction(attrs)
    |> sign_with_key(identity.sign_skey)
  end

  @doc """
  `DialogMessageReceipt` of `type` by `peer_hash`, signed by `identity`.
  `attrs`: `:dialog_hash` (required), `:receipt_hash`, `:message_id`, `:owner_timestamp`.
  """
  def signed_receipt(identity, peer_hash, type, attrs) do
    %DialogMessageReceipt{
      receipt_hash: Keyword.get(attrs, :receipt_hash, generate_receipt_hash()),
      dialog_hash: Keyword.fetch!(attrs, :dialog_hash),
      message_id: Keyword.get(attrs, :message_id, DialogMessageId.generate()),
      peer_hash: peer_hash,
      type: type,
      message_sign_hash: @message_sign_hash,
      owner_timestamp: Keyword.get(attrs, :owner_timestamp, now())
    }
    |> sign_with_key(identity.sign_skey)
  end

  @doc "Random `DialogMessageReactionHash`."
  def generate_reaction_hash do
    :crypto.strong_rand_bytes(64) |> DialogMessageReactionHash.from_binary()
  end

  @doc "Random `DialogMessageReceiptHash`."
  def generate_receipt_hash do
    :crypto.strong_rand_bytes(64) |> DialogMessageReceiptHash.from_binary()
  end

  defp now, do: System.os_time(:millisecond)
end
