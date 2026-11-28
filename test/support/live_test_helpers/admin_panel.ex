defmodule ChatWeb.LiveTestHelpers.AdminPanel do
  @moduledoc """
  Setup shared by the admin panel LiveView tests.
  """

  alias Chat.{AdminDb, Db}
  alias Chat.User.UsersBroker

  @doc "Named setup: clears both CubDB databases, disables admin DB auto-compaction and resyncs users."
  def reset_admin_db(_context) do
    CubDB.clear(AdminDb.db())
    CubDB.clear(Db.db())
    CubDB.set_auto_compact(AdminDb.db(), false)
    UsersBroker.sync()
  end
end
