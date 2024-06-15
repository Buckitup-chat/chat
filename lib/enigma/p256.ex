defmodule Enigma.P256 do
  @moduledoc """
  Elliptic curve P256 aka secp256r1
  """

  @curve :secp256r1
  # @asn1_curve {:namedCurves, {1, 2, 840, 10045, 3, 1, 7}}
  @asn1_curve {:namedCurve, :pubkey_cert_records.namedCurves(@curve)}

  def generate_key do
    X509.PrivateKey.new_ec(@curve)
  end

  def derive_public_key(private) do
    X509.PublicKey.derive(private)
  end

  def sign(data, private) do
    :public_key.sign(data, :sha256, private)
  end

  def valid_sign?(data, sign, public) do
    full_public_key = {public |> parse_public_key(), @asn1_curve}
    :public_key.verify(data, :sha256, sign, full_public_key)
  end

  def ecdh(private, public) do
    :public_key.compute_key(
      public |> parse_public_key(),
      private |> parse_private_key()
    )
  end

  defp parse_private_key(key) do
    case key do
      {:ECPrivateKey, _, _private, _curve, _public, :asn1_NOVALUE} -> key
    end
  end

  defp parse_public_key(key) do
    case key do
      {point = {:ECPoint, _public}, _curve} -> point
      str when is_binary(str) -> {:ECPoint, str}
    end
  end
end
