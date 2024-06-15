defmodule Bucket.Identity.Behavior do
  @moduledoc """
  Behavior for Bucket Identity
  """

  @callback ready?() :: boolean

  @callback get_pub_key() :: String.t()

  @callback compute_secret(String.t()) :: String.t()

  @callback digest(String.t()) :: String.t()
end
