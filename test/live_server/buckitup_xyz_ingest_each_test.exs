defmodule Chat.LiveServer.BuckitupXyzIngestEachTest do
  @moduledoc """
  Fires a real request at `https://buckitup.xyz/electric/v1/ingest_each`,
  reproducing the batch shape captured in `fresh_logs/Request.txt` — a new
  `dialog_messages` insert bundled with two `dialog_message_reactions`
  retractions under a single Proof-of-Possession signature — but with:

    * two freshly created sandbox users (via the app's own `user_sandbox_live`
      Electric API client — no direct DB/cookie access), instead of the real
      captured account
    * a brand new dialog, message and reactions, instead of replaying the
      captured (already one-time-used, 60s-expiry) history
    * a fresh `/electric/v1/challenge` + signature, instead of the captured
      (single-use, long-expired) challenge/signature

  This makes real, permanent-ish writes against a live external host. It is
  intentionally excluded from the default suite (see `test/test_helper.exs`)
  so `mix test` / `make test` / CI never hit the network. Run explicitly:

      mix test --include live_server test/live_server/buckitup_xyz_ingest_each_test.exs

  Note: the captured request's reaction-retraction mutations sent literal
  `"type_b64": ""`. Locally, `DialogMessageReaction.update_changeset/2`
  rejects that — Ecto's `validate_required/2` treats an empty binary as
  blank — so those two mutations in the original capture most likely came
  back as per-mutation validation errors (422 `"can't be blank"`) rather
  than a slow success. This test instead sends a properly encrypted
  empty-emoji blob for the retraction, matching what the shipped
  `DialogSandboxLive.ApiClient.delete_reaction/3` reference client does, so
  the mutations actually succeed.
  """

  use ExUnit.Case, async: false

  @moduletag :live_server
  @moduletag timeout: 60_000

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas.DialogMessage
  alias Chat.Data.Schemas.DialogMessageReaction
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Types.DialogMessageId
  alias Chat.TimeKeeper
  alias ChatWeb.ElectricLive.DialogSandboxLive.ApiClient, as: DialogSandbox
  alias ChatWeb.ElectricLive.DialogSandboxLive.Content
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.UserSandboxLive.ApiClient, as: UserSandbox

  @base_url "https://buckitup.xyz"

  test "sends a message and retracts two earlier reactions in one live ingest_each call" do
    suffix = "#{System.os_time(:second)}-#{System.unique_integer([:positive])}"

    {:ok, %{user: alice}} = UserSandbox.create_user("Sandbox Alice #{suffix}", @base_url)
    {:ok, %{user: bob}} = UserSandbox.create_user("Sandbox Bob #{suffix}", @base_url)

    on_exit(fn ->
      soft_delete_user(alice)
      soft_delete_user(bob)
    end)

    {:ok, %{dialog_hash: dialog_hash}} =
      DialogSandbox.publish_dialog_key(alice, bob.user_hash, bob.crypt_pkey, @base_url)

    {:ok, _} =
      DialogSandbox.publish_dialog_key(bob, alice.user_hash, alice.crypt_pkey, @base_url)

    refs = %{peer_hash: bob.user_hash, tails: %{}}

    {:ok, %{message_id: msg1_id, sign_hash: msg1_sign_hash}} =
      DialogSandbox.publish_dialog_message(
        alice,
        dialog_hash,
        "sandbox message one #{suffix}",
        refs,
        @base_url
      )

    {:ok, %{message_id: msg2_id, sign_hash: msg2_sign_hash}} =
      DialogSandbox.publish_dialog_message(
        alice,
        dialog_hash,
        "sandbox message two #{suffix}",
        refs,
        @base_url
      )

    reaction1 =
      publish_reaction!(bob, dialog_hash, msg1_id, msg1_sign_hash, "👍", alice.user_hash)

    reaction2 =
      publish_reaction!(bob, dialog_hash, msg2_id, msg2_sign_hash, "🔥", alice.user_hash)

    new_message = build_signed_message(bob, dialog_hash, alice.user_hash, suffix)
    retraction1 = retracted(bob, reaction1, alice.user_hash)
    retraction2 = retracted(bob, reaction2, alice.user_hash)

    payload = %{
      "mutations" => [
        message_insert_mutation(new_message, dialog_hash, bob.user_hash),
        reaction_update_mutation(reaction1, retraction1),
        reaction_update_mutation(reaction2, retraction2)
      ]
    }

    {:ok, challenge_resp} = get_challenge()
    {:ok, %{status: status, body: body}} = post_ingest_each(challenge_resp, payload, bob.sign_skey)

    assert status == 200, "ingest_each failed: #{inspect(body)}"
    assert %{"results" => results} = body
    assert length(results) == 3
    assert Enum.all?(results, &(&1["status"] == "ok")), inspect(results)
    assert Enum.all?(results, &is_integer(&1["txid"]))
  end

  # --- Helpers ---

  defp publish_reaction!(user, dialog_hash, message_id, message_sign_hash, emoji, peer_hash) do
    sender_msg_key = sender_msg_key(user, peer_hash)
    reaction_hash = Crypto.compute_reaction_hash(sender_msg_key, message_id, user.user_hash, emoji)
    type_b64 = Crypto.encrypt_emoji(emoji, sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    reaction = %DialogMessageReaction{
      reaction_hash: reaction_hash,
      dialog_hash: dialog_hash,
      message_id: message_id,
      message_sign_hash: message_sign_hash,
      reactor_hash: user.user_hash,
      type_b64: type_b64,
      deleted_flag: false,
      owner_timestamp: owner_timestamp
    }

    reaction = %{reaction | sign_b64: sign(reaction, user.sign_skey)}

    {:ok, _} =
      DialogSandbox.publish_reaction(user, dialog_hash, message_id, message_sign_hash, emoji, peer_hash, @base_url)

    reaction
  end

  defp retracted(user, reaction, peer_hash) do
    sender_msg_key = sender_msg_key(user, peer_hash)
    type_b64 = Crypto.encrypt_emoji("", sender_msg_key)

    updated = %{
      reaction
      | deleted_flag: true,
        owner_timestamp: reaction.owner_timestamp + 1,
        type_b64: type_b64
    }

    %{updated | sign_b64: sign(updated, user.sign_skey)}
  end

  defp sender_msg_key(user, peer_hash) do
    Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)
  end

  defp build_signed_message(user, dialog_hash, peer_hash, suffix) do
    sender_msg_key = sender_msg_key(user, peer_hash)
    content_b64 = Crypto.encrypt_content(Content.prepare_for_send("hi from ingest_each #{suffix}"), sender_msg_key)
    refs_map_b64 = Crypto.encrypt_refs_map(%{}, sender_msg_key)
    owner_timestamp = TimeKeeper.now_unix()

    msg = %DialogMessage{
      message_id: DialogMessageId.generate(),
      dialog_hash: dialog_hash,
      sender_hash: user.user_hash,
      content_b64: content_b64,
      deleted_flag: false,
      refs_map_b64: refs_map_b64,
      parent_sign_hash: nil,
      owner_timestamp: owner_timestamp
    }

    sign_b64 = sign(msg, user.sign_skey)
    sign_hash = Crypto.compute_sign_hash(sign_b64)
    %{msg | sign_b64: sign_b64, sign_hash: sign_hash}
  end

  defp message_insert_mutation(msg, dialog_hash, sender_hash) do
    %{
      "type" => "insert",
      "modified" => %{
        "message_id" => msg.message_id,
        "dialog_hash" => dialog_hash,
        "sender_hash" => sender_hash,
        "content_b64" => encode_base64(msg.content_b64),
        "deleted_flag" => false,
        "refs_map_b64" => encode_base64(msg.refs_map_b64),
        "parent_sign_hash" => nil,
        "owner_timestamp" => msg.owner_timestamp,
        "sign_b64" => encode_base64(msg.sign_b64),
        "sign_hash" => msg.sign_hash
      },
      "syncMetadata" => %{"relation" => "dialog_messages"}
    }
  end

  defp reaction_update_mutation(original, updated) do
    %{
      "type" => "update",
      "original" => %{
        "reaction_hash" => original.reaction_hash,
        "reactor_hash" => original.reactor_hash,
        "dialog_hash" => original.dialog_hash,
        "message_id" => original.message_id
      },
      "changes" => %{
        "type_b64" => encode_base64(updated.type_b64),
        "deleted_flag" => updated.deleted_flag,
        "owner_timestamp" => updated.owner_timestamp,
        "sign_b64" => encode_base64(updated.sign_b64)
      },
      "syncMetadata" => %{"relation" => "dialog_message_reactions"}
    }
  end

  defp soft_delete_user(user) do
    new_timestamp = user.owner_timestamp + 1

    updated_card =
      UserCard
      |> struct(user)
      |> Map.put(:deleted_flag, true)
      |> Map.put(:owner_timestamp, new_timestamp)

    sign_b64 = sign(updated_card, user.sign_skey)

    payload = %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => %{"user_hash" => user.user_hash},
          "changes" => %{
            "deleted_flag" => true,
            "owner_timestamp" => new_timestamp,
            "sign_b64" => encode_base64(sign_b64)
          },
          "syncMetadata" => %{"relation" => "user_cards"}
        }
      ]
    }

    with {:ok, challenge_resp} <- get_challenge(),
         {:ok, %{status: status}} <- post_ingest_each(challenge_resp, payload, user.sign_skey) do
      status
    end
  end

  defp sign(struct_or_map, sign_skey) do
    struct_or_map
    |> Integrity.signature_payload()
    |> EnigmaPq.sign(sign_skey)
  end

  defp encode_base64(bin) when is_binary(bin), do: Base.encode64(bin, padding: false)

  defp get_challenge do
    case Req.get(@base_url <> "/electric/v1/challenge", headers: [{"accept", "application/json"}]) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      other -> {:error, other}
    end
  end

  defp post_ingest_each(%{"challenge" => challenge, "challenge_id" => challenge_id}, payload, sign_skey) do
    signature_b64 = challenge |> EnigmaPq.sign(sign_skey) |> Base.encode64(padding: false)

    payload_with_auth =
      Map.put(payload, "auth", %{"challenge_id" => challenge_id, "signature" => signature_b64})

    Req.post(@base_url <> "/electric/v1/ingest_each",
      json: payload_with_auth,
      headers: [{"accept", "application/json"}, {"content-type", "application/json"}]
    )
  end
end
