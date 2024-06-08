defmodule Enigma.P256Test do
  use ExUnit.Case, async: true

  alias Enigma.P256

  test "signature should work" do
    %{}
    |> generate_key_pair(:alice)
    |> generate_nonce
    |> sign_with_private_key
    |> assert_signature_is_valid
  end

  test "secret calulation and key derivation should work" do
    %{}
    |> generate_key_pair(:alice)
    |> generate_key_pair(:bob)
    |> calculate_shared_secret(from: :alice, to: :bob)
    |> calculate_shared_secret(from: :bob, to: :alice)
    |> assert_shared_secret_is_the_same
  end

  defp generate_key_pair(context, person) do
    priv_key = P256.generate_key()
    pub_key = P256.derive_public_key(priv_key)

    %{priv_key: priv_key, pub_key: pub_key}
    |> save_as(context, person)
  end

  defp generate_nonce(context), do: Map.put(context, :nonce, :crypto.strong_rand_bytes(42))

  defp sign_with_private_key(context),
    do: P256.sign(context.nonce, context.alice.priv_key) |> save_as(context, :signature)

  defp assert_signature_is_valid(context) do
    tap(context, fn context ->
      assert P256.valid_sign?(context.nonce, context.signature, context.alice.pub_key)
    end)
  end

  defp calculate_shared_secret(context, from: from, to: to) do
    P256.ecdh(context[from].priv_key, context[to].pub_key)
    |> save_as(context, "shared_secret_#{from}")
  end

  defp assert_shared_secret_is_the_same(context) do
    tap(context, fn context ->
      assert context["shared_secret_alice"] == context["shared_secret_bob"]
    end)
  end

  defp save_as(value, map, key), do: Map.put(map, key, value)
end
