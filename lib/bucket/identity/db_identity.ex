defmodule Bucket.Identity.DbIdentity do
  @moduledoc """
  Identity module for DB
  """
  @behaviour Bucket.Identity.Behavior

  alias Bucket.Identity.DbIdentity

  defstruct [:pub_key, :priv_key]

  @impl Bucket.Identity.Behavior
  def get_pub_key do
    {{:ECPoint, pub_key}, _} = get_identity().pub_key
    pub_key
  end

  @impl Bucket.Identity.Behavior
  def compute_secret(pub_key) do
    get_identity().priv_key
    |> Enigma.P256.ecdh(pub_key)
  end

  @impl Bucket.Identity.Behavior
  def digest(data) do
    Enigma.P256.sign(data, get_identity().priv_key)
  end

  @impl Bucket.Identity.Behavior
  def ready? do
    match?(%DbIdentity{}, get_identity_or_create())
  end

  defp get_identity_or_create do
    get_identity()
    |> case do
      %DbIdentity{} = identity -> identity
      _ -> create_identity()
    end
  end

  defp create_identity do
    Enigma.P256.generate_key()
    |> new()
    |> tap(&Chat.AdminDb.put(:identity, &1))
  end

  defp new(priv_key) do
    %DbIdentity{
      pub_key: Enigma.P256.derive_public_key(priv_key),
      priv_key: priv_key
    }
  end

  defp get_identity do
    Chat.AdminDb.get(:identity)
  end
end
