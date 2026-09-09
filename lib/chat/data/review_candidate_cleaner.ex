defmodule Chat.Data.ReviewCandidateCleaner do
  @moduledoc "Periodic cleanup of stale review password and right candidates."

  use GenServer

  import Tools.GenServerHelpers, only: [noreply: 1]

  alias Chat.Data.ReviewPasswordCandidate, as: PasswordCandidateData
  alias Chat.Data.ReviewRightCandidate, as: RightCandidateData

  @max_age_seconds 3600
  @cleanup_interval_ms 600_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @impl true
  def init(_) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    PasswordCandidateData.delete_stale_candidates(@max_age_seconds)
    RightCandidateData.delete_stale_candidates(@max_age_seconds)
    schedule_cleanup()
    noreply(state)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
