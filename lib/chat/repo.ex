defmodule Chat.Repo do
  use Phoenix.Sync.Sandbox.Postgres

  use Ecto.Repo,
    otp_app: :chat,
    adapter: Phoenix.Sync.Sandbox.Postgres.adapter()

  if Mix.env() == :test do
    # Phoenix.Sync.Writer.txid_step only matches Ecto.Adapters.Postgres but the
    # sandbox adapter reports as Phoenix.Sync.Sandbox.Postgres.Adapter, causing
    # Writer to skip the txid query. Override __adapter__/0 to return the base
    # adapter while allowing validate_sandbox_repo! to pass via a process flag.
    # Actual DB operations still use the sandbox adapter (compiled into @adapter).
    defoverridable __adapter__: 0

    def __adapter__ do
      if Process.get(:phoenix_sync_validating) do
        Phoenix.Sync.Sandbox.Postgres.Adapter
      else
        Ecto.Adapters.Postgres
      end
    end
  end
end
