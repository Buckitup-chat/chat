defmodule Chat.Test.UnitARepo do
  @moduledoc "Test repo for the first database of the PG pair (`chat_test_unit_a`). See `Chat.Test.PgPairCase`."

  use Ecto.Repo,
    otp_app: :chat,
    adapter: Ecto.Adapters.Postgres
end
