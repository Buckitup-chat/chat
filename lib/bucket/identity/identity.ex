defmodule Bucket.Identity do
  @moduledoc """
  Identity switcher

  It can be used to select backend ion startup. and redirect all calls to selected backend
  Likely CryproChip or AdminDb backends.
  """
  @behaviour Bucket.Identity.Behavior

  @config_app :chat
  @config_backends_key :identity_backends
  @config_adapter_key :identity_adapter

  @impl Bucket.Identity.Behavior
  def ready? do
    raise "Should not be used from Bucket.Identity. This is bootstrapping of backend"
  end

  @impl Bucket.Identity.Behavior
  def get_pub_key, do: adapter().get_pub_key()

  @impl Bucket.Identity.Behavior
  def compute_secret(pub_key), do: adapter().compute_secret(pub_key)

  @impl Bucket.Identity.Behavior
  def digest(data), do: adapter().digest(data)

  def bootstrap do
    Application.fetch_env!(@config_app, @config_backends_key)
    |> Enum.find(& &1.ready?())
    |> then(&Application.put_env(@config_app, @config_adapter_key, &1))
  end

  defp adapter do
    Application.fetch_env!(@config_app, @config_adapter_key)
  end
end
