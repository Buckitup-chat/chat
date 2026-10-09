defmodule Chat.NetworkSynchronization.Electric.GatedFetch do
  @moduledoc """
  `Electric.Client.Fetch` for peer shape streams behind the peer's read gate.

  Wraps `Electric.Client.Fetch.HTTP`: sends the read-session Bearer token for
  `:shape` on `:peer_url` and, on `401 read_session_required`, opens a session
  and retries the same request once — the stream keeps its offset.

  When the session cannot be opened the fetch fails with
  `{:read_session, reason}` (see `ReadSessions.blocked_by/1`).

  Options: `:peer_url`, `:shape`, optional `:read_sessions` (server name);
  the rest go to `Electric.Client.Fetch.HTTP`.
  """

  @behaviour Electric.Client.Fetch

  alias Chat.NetworkSynchronization.Electric.ReadSessions
  alias Electric.Client.Fetch

  @gate_keys [:peer_url, :shape, :read_sessions]

  @impl true
  def validate_opts(opts) do
    {gate_opts, http_opts} = Keyword.split(opts, @gate_keys)

    with {:gate, true} <-
           {:gate, Enum.all?([:peer_url, :shape], &Keyword.has_key?(gate_opts, &1))},
         {:ok, http_opts} <- Fetch.HTTP.validate_opts(http_opts) do
      {:ok, gate_opts ++ http_opts}
    else
      {:gate, false} -> {:error, "GatedFetch requires :peer_url and :shape"}
      error -> error
    end
  end

  @impl true
  def fetch(request, opts) do
    {gate_opts, http_opts} = Keyword.split(opts, @gate_keys)

    fetch_with_headers = fn headers ->
      request
      |> Map.update!(:headers, &Map.merge(&1, Map.new(headers)))
      |> Fetch.HTTP.fetch(http_opts)
    end

    ReadSessions.request(
      Keyword.fetch!(gate_opts, :peer_url),
      Keyword.fetch!(gate_opts, :shape),
      fetch_with_headers,
      Keyword.get(gate_opts, :read_sessions, ReadSessions)
    )
  end
end
