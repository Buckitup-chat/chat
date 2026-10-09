defmodule ChatWeb.ElectricLive.SandboxGatedFetch do
  @moduledoc """
  `Electric.Client.Fetch` wrapper that opens a read session on `401 read_session_required`.

  Used by sandbox streams (`Electric.Client.stream`) that hit the gated shapes endpoint.
  Caches the token in the process dictionary — each spawned stream process gets its own.

  Options (alongside `Fetch.HTTP` options):
    * `:base_url` — the Electric host URL
    * `:user_hash` — caller identity
    * `:sign_skey` — ML-DSA-87 signing key for PoP
  """

  @behaviour Electric.Client.Fetch

  alias ChatWeb.ElectricLive.SandboxHttp
  alias Electric.Client.Fetch

  @gate_keys [:base_url, :user_hash, :sign_skey]

  @doc "Builds an `Electric.Client` that authenticates shape reads with the server identity."
  def client do
    identity = Chat.Pq.ServerIdentity.get()

    Electric.Client.new!(
      endpoint: ChatWeb.Endpoint.url() <> "/electric/v1/shapes",
      fetch:
        {__MODULE__,
         [
           base_url: ChatWeb.Endpoint.url(),
           user_hash: Chat.Pq.ServerIdentity.user_hash(),
           sign_skey: identity.sign_skey
         ]}
    )
  end

  @impl true
  def validate_opts(opts) do
    {gate_opts, http_opts} = Keyword.split(opts, @gate_keys)

    with {:ok, http_opts} <- Fetch.HTTP.validate_opts(http_opts) do
      {:ok, gate_opts ++ http_opts}
    end
  end

  @impl true
  def fetch(request, opts) do
    {gate_opts, http_opts} = Keyword.split(opts, @gate_keys)
    request = maybe_inject_token(request)
    result = Fetch.HTTP.fetch(request, http_opts)

    case result do
      {:ok,
       %Fetch.Response{
         status: 401,
         body: %{"error" => "read_session_required", "shape" => shape}
       }} ->
        case open_and_cache(gate_opts, shape) do
          {:ok, token} ->
            request |> inject_token(token) |> Fetch.HTTP.fetch(http_opts)

          :error ->
            result
        end

      _ ->
        result
    end
  end

  defp maybe_inject_token(request) do
    case Process.get(:sandbox_read_token) do
      {token, expires_at} ->
        if expires_at > System.monotonic_time(:millisecond),
          do: inject_token(request, token),
          else: request

      _ ->
        request
    end
  end

  defp inject_token(request, token) do
    Map.update!(request, :headers, &Map.put(&1, "authorization", "Bearer #{token}"))
  end

  defp open_and_cache(gate_opts, shape) do
    case SandboxHttp.open_read_session(
           gate_opts[:base_url],
           shape,
           gate_opts[:user_hash],
           gate_opts[:sign_skey]
         ) do
      {:ok, token, expires_in, _logs} ->
        expires_at = System.monotonic_time(:millisecond) + :timer.seconds(expires_in)
        Process.put(:sandbox_read_token, {token, expires_at})
        {:ok, token}

      {:error, _reason, _logs} ->
        :error
    end
  end
end
