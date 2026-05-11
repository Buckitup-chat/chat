defmodule Chat.NetworkSynchronization.Electric.DeferredRecord do
  @moduledoc "A record deferred because its parent shape hasn't arrived yet"

  @enforce_keys [:shape, :key, :operation, :missing_parents, :peer_url, :deferred_at]
  defstruct [:shape, :key, :operation, :missing_parents, :peer_url, :deferred_at]

  @type t :: %__MODULE__{
          shape: atom(),
          key: Keyword.t(),
          operation: :insert | :update,
          missing_parents: [{atom(), term()}],
          peer_url: String.t(),
          deferred_at: integer()
        }

  @spec new(atom(), Keyword.t(), :insert | :update, [{atom(), term()}], String.t()) :: t()
  def new(shape, key, operation, missing_parents, peer_url) do
    %__MODULE__{
      shape: shape,
      key: key,
      operation: operation,
      missing_parents: missing_parents,
      peer_url: peer_url,
      deferred_at: System.monotonic_time(:millisecond)
    }
  end
end
