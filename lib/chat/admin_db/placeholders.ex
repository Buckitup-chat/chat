defmodule Chat.AdminDb.Placeholders do
  @moduledoc "Handles AdminDb placeholders"
  alias Chat.Db.Maintenance

  @placeholder_prefix "dump"
  @placeholder_size 20 * 1024 * 1024
  @placeholders_num 5

  def manage(db, folder_path) do
    if has_free_space(db) do
      restore(folder_path)
    else
      remove_single(folder_path)
    end
  end

  defp has_free_space(db) do
    Maintenance.db_free_space(db) > @placeholder_size * @placeholders_num
  end

  defp restore(folder_path) do
    with {:ok, _} <- remove_folder(folder_path),
         :ok <- File.mkdir(folder_path),
         data <- :crypto.strong_rand_bytes(@placeholder_size) do
      for i <- 1..@placeholders_num do
        file_path = Path.join(folder_path, "#{@placeholder_prefix}#{i}.txt")
        File.open(file_path, [:write, :binary], fn file -> IO.binwrite(file, data) end)
      end
    end
  end

  defp remove_single(folder_path) do
    folder_path
    |> File.ls!()
    |> case do
      [] ->
        :ignore

      list ->
        Enum.random(list)
        |> then(&Path.join(folder_path, &1))
        |> File.rm()
    end
  end

  defp remove_folder(folder_path) do
    if File.exists?(folder_path) do
      File.rm_rf(folder_path)
    else
      {:ok, []}
    end
  end
end
