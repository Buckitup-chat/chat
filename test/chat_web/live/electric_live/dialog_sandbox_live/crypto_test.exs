defmodule ChatWeb.ElectricLive.DialogSandboxLive.CryptoTest do
  use ExUnit.Case, async: true

  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto

  describe "reaction decryption / [no key]" do
    test "reactor reads their own reaction (own key always in cache)" do
      alice = build_user()
      bob = build_user()

      reaction = react(alice, bob, "👍")
      cache = own_key_cache(alice, bob)

      assert decrypt(reaction, cache) == "👍"
    end

    test "peer reads the reaction once the reactor has published their dialog key" do
      alice = build_user()
      bob = build_user()

      reaction = react(alice, bob, "🎉")
      # Alice published her dialog key, so Bob can unwrap Alice's sender_msg_key.
      cache = cache_with_unwrapped_peer_key(bob, alice)

      assert decrypt(reaction, cache) == "🎉"
    end

    test "peer sees [no key] when the reactor never published their dialog key" do
      alice = build_user()
      bob = build_user()

      # Bob created the dialog (published his key); Alice only reacted and never
      # published hers, so Bob has no way to obtain Alice's sender_msg_key.
      reaction = react(alice, bob, "🔥")
      cache = own_key_cache(bob, alice)

      assert decrypt(reaction, cache) == "[no key]"
    end
  end

  # --- helpers ---

  # A reaction map shaped like a row returned from the reactions shape endpoint:
  # reactor_hash as `u_<hex>` text and type_b64 as unpadded base64 of the blob.
  defp react(reactor, peer, emoji) do
    key = sender_msg_key(reactor, peer.user_hash)
    blob = Crypto.encrypt_emoji(emoji, key)

    %{
      "reactor_hash" => reactor.user_hash,
      "message_id" => "msg-1",
      "message_sign_hash" => "sgn-1",
      "type_b64" => Base.encode64(blob, padding: false),
      "deleted_flag" => false
    }
  end

  defp decrypt(reaction, cache), do: Crypto.decrypt_single_reaction(reaction, cache).emoji

  # The viewer always holds their own derived key; the peer's key is absent.
  defp own_key_cache(viewer, peer) do
    %{viewer.user_hash => sender_msg_key(viewer, peer.user_hash)}
  end

  # The viewer holds their own key plus the peer's key, recovered by unwrapping the
  # peer's published dialog key — exactly the maybe_unwrap_peer_key/4 path.
  defp cache_with_unwrapped_peer_key(viewer, peer) do
    peer_key = sender_msg_key(peer, viewer.user_hash)
    {kem_wrap, wrapped} = Crypto.wrap_for_peer(peer_key, viewer.crypt_pkey)
    unwrapped = Crypto.unwrap_peer_key(kem_wrap, wrapped, viewer.crypt_skey)

    viewer
    |> own_key_cache(peer)
    |> Map.put(peer.user_hash, unwrapped)
  end

  describe "parse_and_validate_identity/1" do
    test "accepts an export whose secret key matches its public key" do
      keys = identity_keys()

      assert {:ok, %{user_hash: user_hash}} =
               keys |> identity_json() |> Crypto.parse_and_validate_identity()

      assert user_hash == keys.user_hash
    end

    test "refuses a published public key paired with another secret key" do
      owner = identity_keys()
      json = identity_json(%{owner | sign_skey: identity_keys().sign_skey})

      assert Crypto.parse_and_validate_identity(json) ==
               {:error, "sign_skey does not match sign_pkey"}
    end

    test "refuses a public key with a malformed secret key" do
      json = identity_json(%{identity_keys() | sign_skey: ""})

      assert Crypto.parse_and_validate_identity(json) ==
               {:error, "sign_skey does not match sign_pkey"}
    end
  end

  defp identity_keys do
    {sign_pkey, sign_skey} = EnigmaPq.generate_sign_keypair()
    {crypt_pkey, crypt_skey} = EnigmaPq.generate_crypt_keypair()
    {contact_pkey, contact_skey} = EnigmaPq.generate_crypt_keypair()

    %{
      user_hash: sign_pkey |> EnigmaPq.hash() |> Chat.Data.Types.UserHash.from_binary(),
      sign_pkey: sign_pkey,
      sign_skey: sign_skey,
      crypt_pkey: crypt_pkey,
      crypt_skey: crypt_skey,
      crypt_cert: EnigmaPq.sign(crypt_pkey, sign_skey),
      contact_pkey: contact_pkey,
      contact_skey: contact_skey,
      contact_cert: EnigmaPq.sign(contact_pkey, sign_skey)
    }
  end

  defp identity_json(keys) do
    keys
    |> Map.drop([:user_hash])
    |> Map.new(fn {field, bin} -> {field, Base.encode64(bin, padding: false)} end)
    |> Map.merge(%{
      type: "buckitup_pq_identity",
      version: 2,
      user_hash: keys.user_hash,
      name: "Owner"
    })
    |> Jason.encode!()
  end

  defp sender_msg_key(user, peer_hash) do
    Crypto.derive_sender_msg_key(user.sign_skey, user.crypt_skey, user.contact_skey, peer_hash)
  end

  defp build_user do
    Map.take(identity_keys(), [:user_hash, :sign_skey, :crypt_pkey, :crypt_skey, :contact_skey])
  end
end
