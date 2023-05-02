defmodule Chat.Db.DbType do
  @moduledoc """
  Saves and reads DB type from the database. Used by `Platform.Storage.Bouncer`
  to determine whether the DB directory has been renamed.
  """

  def get(db) do
    CubDB.get(db, :db_type)
  end

  def put(db, type) do
    CubDB.put(db, :db_type, type)
  end
end
