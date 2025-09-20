defmodule Chat.Repo do
  use Ecto.Repo,
    otp_app: :chat,
    adapter: Ecto.Adapters.Postgres

  def with_dynamic_repo(repo, fun) do
    old_repo = Chat.Repo.get_dynamic_repo()
    repo_pid = Process.whereis(repo)

    if is_pid(repo_pid) do
      Chat.Repo.put_dynamic_repo(repo)

      fun.()
      |> tap(fn _ -> Chat.Repo.put_dynamic_repo(old_repo) end)
    end
  end
end
