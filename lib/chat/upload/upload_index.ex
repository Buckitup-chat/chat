defmodule Chat.Upload.UploadIndex do
  @moduledoc "Keeps an index of uploads"

  alias Chat.Db
  alias Chat.Upload.Upload

  def add(key, %Upload{} = upload) do
    Db.put({:upload_index, key}, upload)
  end

  def get(key) do
    Db.get({:upload_index, key})
  end

  def list do
    Db.list({{:upload_index, 0}, {:"upload_index\0", 0}}, fn {{:upload_index, key},
                                                              %Upload{} = upload} ->
      {key, upload}
    end)
  end

  def delete(key) do
    Db.delete({:upload_index, key})
  end
end
