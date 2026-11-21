defmodule Chat.ReviewBot.Worker do
  @moduledoc "GenServer for a running review bot. Holds decrypted identity, never exposes secret keys."

  use GenServer, restart: :transient

  import Tools.GenServerHelpers

  alias Chat.Pq.Ingest
  alias Chat.ReviewBot.Identity
  alias EnigmaPq

  def start_link(%{bot_hash: bot_hash} = init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: via(bot_hash))
  end

  def whereis(bot_hash) do
    case Registry.lookup(Chat.ReviewBot.Registry, bot_hash) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def running?(bot_hash), do: whereis(bot_hash) != nil

  def ingest(bot_hash, mutations) do
    GenServer.call(via(bot_hash), {:ingest, mutations})
  end

  def sign(bot_hash, payload) do
    GenServer.call(via(bot_hash), {:sign, payload})
  end

  def wrap_nonce(bot_hash, nonce) do
    GenServer.call(via(bot_hash), {:wrap_nonce, nonce})
  end

  def unwrap_nonce(bot_hash, nonce_enc) do
    GenServer.call(via(bot_hash), {:unwrap_nonce, nonce_enc})
  end

  def info(bot_hash) do
    GenServer.call(via(bot_hash), :info)
  end

  def verify_auth(bot_hash, bearer) do
    GenServer.call(via(bot_hash), {:verify_auth, bearer})
  end

  # --- Callbacks ---

  @impl true
  def init(%{bot_hash: bot_hash, origin_hash: origin_hash, identity: identity} = init_arg) do
    Process.flag(:sensitive, true)

    %{
      bot_hash: bot_hash,
      origin_hash: origin_hash,
      identity: identity,
      auth_token: Map.get(init_arg, :auth_token)
    }
    |> ok()
  end

  @impl true
  def handle_call({:ingest, mutations}, _from, state) do
    result = Ingest.apply(mutations, Ingest.self_pop(state.identity.sign_skey))
    state |> reply(result)
  end

  def handle_call({:sign, payload}, _from, state) do
    signature = EnigmaPq.sign(payload, state.identity.sign_skey)
    state |> reply(signature)
  end

  def handle_call({:wrap_nonce, nonce}, _from, state) do
    state |> reply(Identity.wrap_nonce(nonce, state.identity.crypt_skey))
  end

  def handle_call({:unwrap_nonce, nonce_enc}, _from, state) do
    state |> reply(Identity.unwrap_nonce(nonce_enc, state.identity.crypt_skey))
  end

  def handle_call(:info, _from, state) do
    state |> reply(%{bot_hash: state.bot_hash, origin_hash: state.origin_hash})
  end

  def handle_call({:verify_auth, _bearer}, _from, %{auth_token: nil} = state) do
    state |> reply({:error, :no_auth_token_configured})
  end

  def handle_call({:verify_auth, bearer}, _from, state) do
    case Plug.Crypto.secure_compare(state.auth_token, bearer) do
      true -> state |> reply(:ok)
      false -> state |> reply({:error, :invalid_auth_token})
    end
  end

  # `:sensitive` hides state from tracing only; `:sys.get_status` and crash reports still need this.
  @impl true
  def format_status(status) do
    Map.update(status, :state, :redacted, fn
      %{identity: _} = state -> %{state | identity: :redacted, auth_token: :redacted}
      other -> other
    end)
  end

  defp via(bot_hash), do: {:via, Registry, {Chat.ReviewBot.Registry, bot_hash}}
end
