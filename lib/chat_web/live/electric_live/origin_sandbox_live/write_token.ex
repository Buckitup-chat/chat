defmodule ChatWeb.ElectricLive.OriginSandboxLive.WriteToken do
  @moduledoc "LiveView component and event handling for write tokens in the origin sandbox."

  use Phoenix.Component

  alias Chat.Proto.Shortcode
  alias ChatWeb.ElectricLive.OriginSandboxLive.WriteTokenClient

  def handle_create(%{"bot_hash" => bot_hash} = params, base_url, socket) do
    order_hash = params["origin_order_hash"]
    auth_token = params["auth_token"]
    auth_token = if auth_token in [nil, ""], do: nil, else: auth_token

    case WriteTokenClient.create_token(bot_hash, order_hash, auth_token, base_url) do
      {:ok, result, logs} ->
        {:noreply, socket |> assign(:last_token_result, result) |> append_logs(logs)}

      {:error, reason, logs} ->
        {:noreply, socket |> assign(:error_message, reason) |> append_logs(logs)}
    end
  end

  def handle_refresh(base_url, auth, socket) do
    origin = socket.assigns.origin

    case WriteTokenClient.list_tokens(origin.origin_hash, base_url, auth) do
      {:ok, tokens, logs} ->
        {:noreply, socket |> assign(:write_tokens, tokens) |> append_logs(logs)}

      {:error, reason, logs} ->
        {:noreply, socket |> assign(:error_message, reason) |> append_logs(logs)}
    end
  end

  def list_tokens(origin_hash, base_url, auth) do
    case WriteTokenClient.list_tokens(origin_hash, base_url, auth) do
      {:ok, tokens, _logs} -> tokens
      {:error, _reason, _logs} -> []
    end
  end

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))

  def render_token_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <div class="flex justify-between items-center mb-4">
        <h2 class="text-lg font-semibold text-gray-900">Write Tokens</h2>
        <button
          phx-click="refresh_tokens"
          class="px-3 py-1 bg-gray-200 text-gray-700 rounded text-sm hover:bg-gray-300"
        >
          Refresh
        </button>
      </div>

      <%= if has_active_bot?(@origin_bots) do %>
        {render_create_form(assigns)}
        {render_token_list(assigns)}
      <% else %>
        <p class="text-sm text-gray-500">
          Start a review bot to create write tokens.
        </p>
      <% end %>
    </div>
    """
  end

  defp render_create_form(assigns) do
    ~H"""
    <div class="mb-4 border-b pb-4">
      <h3 class="text-sm font-semibold text-gray-700 mb-2">Create Token</h3>
      <form phx-submit="create_write_token" class="flex gap-3 items-end">
        <div>
          <label class="block text-xs font-medium text-gray-700 mb-1">Bot</label>
          <select name="bot_hash" class="px-3 py-2 border rounded-lg text-sm">
            <option :for={bot <- active_bots(@origin_bots)} value={bot.bot_hash}>
              {Shortcode.short_code(bot.bot_hash)}
            </option>
          </select>
        </div>
        <div class="flex-1">
          <label class="block text-xs font-medium text-gray-700 mb-1">Auth token</label>
          <input
            type="text"
            name="auth_token"
            placeholder="Bearer token for bot auth"
            class="w-full px-3 py-2 border rounded-lg text-sm"
          />
        </div>
        <div class="flex-1">
          <label class="block text-xs font-medium text-gray-700 mb-1">
            Order hash <span class="text-gray-400">(optional)</span>
          </label>
          <input
            type="text"
            name="origin_order_hash"
            placeholder="Leave empty for reusable link"
            class="w-full px-3 py-2 border rounded-lg text-sm"
          />
        </div>
        <button
          type="submit"
          class="bg-green-600 text-white px-4 py-2 rounded-lg hover:bg-green-700 text-sm"
        >
          Create
        </button>
      </form>

      <%= if @last_token_result do %>
        <div class="mt-3 bg-green-50 border border-green-200 rounded p-3 text-sm">
          <p class="font-medium text-green-800">Token created</p>
          <p class="text-xs text-gray-600 mt-1">
            <span class="font-medium">Nonce:</span>
            <span class="font-mono">{@last_token_result["nonce"]}</span>
          </p>
          <p class="text-xs text-gray-600 mt-1">
            <span class="font-medium">URL:</span>
            <a
              href={@last_token_result["url"]}
              target="_blank"
              class="font-mono text-blue-600 hover:underline"
            >
              {@last_token_result["url"]}
            </a>
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_token_list(assigns) do
    ~H"""
    <%= if @write_tokens == [] do %>
      <p class="text-sm text-gray-500">No tokens found for this origin.</p>
    <% else %>
      <div class="space-y-2">
        <div
          :for={token <- @write_tokens}
          class={"text-xs p-3 rounded border #{token_border_class(token)}"}
        >
          <div class="flex items-center justify-between">
            <div>
              <span class="font-mono text-gray-600">{truncate_nonce(token.nonce)}</span>
              <span class={"ml-2 font-medium #{token_status_class(token)}"}>
                {token_status(token)}
              </span>
            </div>
            <span class="text-gray-400">ts: {token.owner_timestamp}</span>
          </div>
          <div class="mt-1 space-y-0.5 text-gray-500">
            <p :if={token.bot_hash}>
              <span class="font-medium">Bot:</span> {Shortcode.short_code(token.bot_hash)}
            </p>
            <p :if={token.user_hash}>
              <span class="font-medium">User:</span> {Shortcode.short_code(token.user_hash)}
            </p>
            <p :if={token.review_hash}>
              <span class="font-medium">Review:</span> {Shortcode.short_code(token.review_hash)}
            </p>
            <p :if={token.origin_order_hash}>
              <span class="font-medium">Order:</span> {Shortcode.short_code(token.origin_order_hash)}
            </p>
            <p :if={token.parent_nonce}>
              <span class="font-medium">Parent:</span> {truncate_nonce(token.parent_nonce)}
            </p>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp token_status(token) do
    cond do
      token.deleted_flag -> "soft-deleted"
      token.review_hash -> "reviewed"
      token.user_hash -> "bound"
      true -> "pending"
    end
  end

  defp token_border_class(token) do
    cond do
      token.deleted_flag -> "border-red-200 bg-red-50"
      token.review_hash -> "border-green-200 bg-green-50"
      token.user_hash -> "border-blue-200 bg-blue-50"
      true -> "border-gray-200"
    end
  end

  defp token_status_class(token) do
    cond do
      token.deleted_flag -> "text-red-600"
      token.review_hash -> "text-green-600"
      token.user_hash -> "text-blue-600"
      true -> "text-gray-500"
    end
  end

  defp has_active_bot?(bots), do: Enum.any?(bots, &(not &1.deleted_flag))
  defp active_bots(bots), do: Enum.reject(bots, & &1.deleted_flag)

  defp truncate_nonce(nil), do: "—"
  defp truncate_nonce(nonce) when byte_size(nonce) > 12, do: binary_part(nonce, 0, 12) <> "…"
  defp truncate_nonce(nonce), do: nonce
end
