defmodule Chat.Pq.Ingest do
  @moduledoc """
  Core ingest pipeline for PQ mutations.

  Wraps Phoenix.Sync.Writer configuration and application so that both
  the HTTP controller and server-side callers (e.g. ReviewBotWorker)
  share the same check/validate path.
  """

  import Chat.Db, only: [repo: 0]

  alias Chat.Challenge
  alias Chat.Data.Shapes
  alias Phoenix.Sync.Writer
  alias Phoenix.Sync.Writer.Format

  @ingest_timeout 60_000

  @doc """
  Applies mutations through the full ingest pipeline.

  Returns `{:ok, txid, changes}` or `{:error, ...}`.
  """
  def apply(mutations, pop_context) do
    Writer.new()
    |> config_writer(pop_context)
    |> Writer.apply(mutations, repo(),
      format: Format.TanstackDB,
      timeout: @ingest_timeout
    )
  end

  @doc """
  Builds a PoP context for a server-side caller that holds `sign_skey`.

  Issues a challenge, signs it, and returns the context map
  that shapes' check callbacks expect.
  """
  def self_pop(sign_skey) do
    {_id, challenge} = Challenge.store()
    signature = EnigmaPq.sign(challenge, sign_skey)
    %{challenge: challenge, signature: signature}
  end

  @doc "Configures a Writer with all registered shapes."
  def config_writer(writer, pop_context) do
    Shapes.all()
    |> Enum.reduce(writer, fn shape_mod, w ->
      shape_mod.ingest_configure_writer(w, pop_context)
    end)
  end
end
