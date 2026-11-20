defmodule Chat.Test.UnitBRepo do
  @moduledoc "Test repo for the second database of the PG pair (`chat_test_unit_b`). See `Chat.Test.PgPairCase`."

  use Ecto.Repo,
    otp_app: :chat,
    adapter: Ecto.Adapters.Postgres
end
