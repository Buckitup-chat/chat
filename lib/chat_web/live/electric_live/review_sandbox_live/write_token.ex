defmodule ChatWeb.ElectricLive.ReviewSandboxLive.WriteToken do
  @moduledoc "Component and event handling for write token bind in the review sandbox."

  use Phoenix.Component

  import ChatWeb.ElectricLive.ReviewSandboxLive.State, only: [append_logs: 2]
  import ChatWeb.LiveHelpers, only: [public_url: 1]

  alias Chat.Proto.Shortcode
  alias ChatWeb.ElectricLive.ReviewSandboxLive.WriteTokenClient

  def handle_event("check_token", %{"nonce" => nonce}, socket) do
    nonce = String.trim(nonce)
    auth = auth_from(socket)

    case WriteTokenClient.check_token(nonce, public_url(socket), auth) do
      {:ok, token, logs} ->
        socket
        |> assign(:wt_nonce, nonce)
        |> assign(:wt_token, token)
        |> assign(:wt_error, nil)
        |> append_logs(logs)
        |> noreply()

      {:error, reason, logs} ->
        socket
        |> assign(:wt_error, reason)
        |> assign(:wt_token, nil)
        |> append_logs(logs)
        |> noreply()
    end
  end

  def handle_event("bind_token", _params, socket) do
    %{wt_nonce: nonce, author: author} = socket.assigns

    case WriteTokenClient.bind_token(
           nonce,
           author.user_hash,
           author.sign_skey,
           public_url(socket)
         ) do
      {:ok, resp, logs} ->
        socket
        |> assign(:wt_bind_result, resp)
        |> assign(:wt_error, nil)
        |> append_logs(logs)
        |> load_vouches()
        |> noreply()

      {:error, reason, logs} ->
        socket
        |> assign(:wt_error, reason)
        |> append_logs(logs)
        |> noreply()
    end
  end

  def handle_event("refresh_vouches", _params, socket) do
    socket |> load_vouches() |> noreply()
  end

  def handle_event("wt_form_changed", %{"nonce" => nonce}, socket) do
    socket |> assign(:wt_nonce, nonce) |> noreply()
  end

  defp load_vouches(socket) do
    auth = auth_from(socket)

    case WriteTokenClient.list_vouches(socket.assigns.author.user_hash, public_url(socket), auth) do
      {:ok, vouches, logs} ->
        socket |> assign(:wt_vouches, vouches) |> append_logs(logs)

      {:error, _reason, logs} ->
        append_logs(socket, logs)
    end
  end

  defp auth_from(socket) do
    author = socket.assigns.author
    %{user_hash: author.user_hash, sign_skey: author.sign_skey}
  end

  defp noreply(socket), do: {:noreply, socket}

  def render_write_token_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Write Token</h2>
      <p class="text-sm text-gray-600 mb-3">
        Paste a token nonce (from QR URL) to check its state and bind it to your identity.
      </p>

      <%= if @wt_error do %>
        <div class="mb-3 bg-red-50 border border-red-200 text-red-800 px-3 py-2 rounded text-sm">
          {@wt_error}
        </div>
      <% end %>

      <form phx-submit="check_token" phx-change="wt_form_changed" class="flex gap-3 items-end mb-4">
        <div class="flex-1">
          <label class="block text-xs font-medium text-gray-700 mb-1">Token nonce</label>
          <input
            type="text"
            name="nonce"
            value={@wt_nonce}
            placeholder="Paste nonce here..."
            class="w-full px-3 py-2 border rounded-lg text-sm font-mono"
          />
        </div>
        <button
          type="submit"
          disabled={@wt_nonce == "" or @wt_nonce == nil}
          class={"bg-blue-600 text-white px-4 py-2 rounded-lg text-sm #{if @wt_nonce in ["", nil], do: "opacity-50 cursor-not-allowed", else: "hover:bg-blue-700"}"}
        >
          Check
        </button>
      </form>

      {render_token_state(assigns)}
      {render_bind_result(assigns)}
      {render_vouches(assigns)}
    </div>
    """
  end

  defp render_token_state(assigns) do
    ~H"""
    <%= if @wt_token do %>
      <div class={"mb-4 p-3 rounded border text-sm #{token_border(@wt_token)}"}>
        <p class="font-medium mb-1">
          Token state: <span class={token_status_class(@wt_token)}>{token_status(@wt_token)}</span>
        </p>
        <div class="space-y-0.5 text-xs text-gray-600">
          <p>
            <span class="font-medium">Nonce:</span>
            <span class="font-mono">{@wt_token.nonce}</span>
          </p>
          <p>
            <span class="font-medium">Origin:</span>
            <span class="font-mono">{Shortcode.short_code(@wt_token.origin_hash)}</span>
          </p>
          <p :if={@wt_token.bot_hash}>
            <span class="font-medium">Bot:</span>
            <span class="font-mono">{Shortcode.short_code(@wt_token.bot_hash)}</span>
          </p>
          <p :if={@wt_token.user_hash}>
            <span class="font-medium">User:</span>
            <span class="font-mono">{Shortcode.short_code(@wt_token.user_hash)}</span>
          </p>
          <p :if={@wt_token.review_hash}>
            <span class="font-medium">Review:</span>
            <span class="font-mono">{Shortcode.short_code(@wt_token.review_hash)}</span>
          </p>
          <p :if={@wt_token.origin_order_hash}>
            <span class="font-medium">Order:</span>
            <span class="font-mono">{Shortcode.short_code(@wt_token.origin_order_hash)}</span>
          </p>
          <p><span class="font-medium">Timestamp:</span> {@wt_token.owner_timestamp}</p>
        </div>

        <%= if not @wt_token.deleted_flag and not bound?(@wt_token) and not @wt_bind_result do %>
          <button
            phx-click="bind_token"
            class="mt-3 bg-green-600 text-white px-4 py-2 rounded-lg text-sm hover:bg-green-700"
          >
            Bind to my identity
          </button>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp render_bind_result(assigns) do
    ~H"""
    <%= if @wt_bind_result do %>
      <div class="mb-4 bg-green-50 border border-green-200 rounded p-3 text-sm">
        <p class="font-medium text-green-800">Token bound successfully</p>
        <p class="text-xs text-gray-600 mt-1">
          <span class="font-medium">Bound nonce:</span>
          <span class="font-mono">{@wt_bind_result["nonce"]}</span>
        </p>
        <p :if={@wt_bind_result["url"]} class="text-xs text-gray-600 mt-1">
          <span class="font-medium">URL:</span>
          <span class="font-mono">{@wt_bind_result["url"]}</span>
        </p>
      </div>
    <% end %>
    """
  end

  defp render_vouches(assigns) do
    ~H"""
    <%= if @wt_bind_result do %>
      <div class="border-t pt-3">
        <div class="flex justify-between items-center mb-2">
          <h3 class="text-sm font-semibold text-gray-700">Issued Vouch Tokens</h3>
          <button
            phx-click="refresh_vouches"
            class="px-3 py-1 bg-gray-200 text-gray-700 rounded text-sm hover:bg-gray-300"
          >
            Refresh
          </button>
        </div>
        <%= if @wt_vouches == [] do %>
          <p class="text-xs text-gray-500">No vouch tokens found for this user yet.</p>
        <% else %>
          <div class="space-y-1">
            <div
              :for={v <- @wt_vouches}
              class={"text-xs p-2 rounded border #{if v.deleted_flag, do: "border-red-200 bg-red-50", else: "border-green-200 bg-green-50"}"}
            >
              <span class="font-medium">{v.resource_path}</span>
              <span class="ml-2 text-gray-500">
                from {Shortcode.short_code(v.voucher_hash)}
              </span>
              <span :if={v.deleted_flag} class="ml-2 text-red-600">(deleted)</span>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp token_status(token) do
    cond do
      token.deleted_flag -> "deleted"
      token.review_hash -> "reviewed"
      token.user_hash -> "bound"
      true -> "pending"
    end
  end

  defp token_border(token) do
    cond do
      token.deleted_flag -> "border-red-200 bg-red-50"
      token.review_hash -> "border-green-200 bg-green-50"
      token.user_hash -> "border-blue-200 bg-blue-50"
      true -> "border-gray-200 bg-gray-50"
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

  defp bound?(token), do: token.user_hash != nil
end
