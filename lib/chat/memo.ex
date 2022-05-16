defmodule Chat.Memo do
  @moduledoc "Context for Memo(long text)"

  alias Chat.Db
  alias Chat.Utils

  def get({key, secret}), do: get(key, secret)

  def get(key, secret) do
    blob = Db.get({:memo, key})

    if blob do
      Utils.decrypt_blob(blob, secret)
    end
  end

  def delete({key, _secret}), do: delete(key)

  def delete(key) do
    Db.delete({:memo, key})
  end

  def add(data) do
    key = UUID.uuid4()

    {blob, secret} = Utils.encrypt_blob(data)
    Db.put({:memo, key}, blob)

    {key, secret}
  end
end
