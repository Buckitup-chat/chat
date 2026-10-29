defmodule ChatWeb.ElectricLive.ModerationSandboxLive.ReviewBot do
  @moduledoc "LiveView component for review bot admin within the origin sandbox."

  use Phoenix.Component

  alias Chat.Proto.Shortcode
  alias Chat.ReviewBot.Identity
  alias Chat.ReviewBot.Worker

  def render_bot_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Review Bot</h2>

      <%= if @origin[:origin_crypt_skey] do %>
        {render_bot_controls(assigns)}
      <% else %>
        <p class="text-sm text-gray-500">
          Origin identity keys not available. Export the origin identity first.
        </p>
      <% end %>
    </div>
    """
  end

  defp render_bot_controls(assigns) do
    ~H"""
    <%= if @origin_bots == [] do %>
      <p class="text-sm text-gray-600 mb-3">No review bot configured for this origin.</p>
      <button
        phx-click="create_review_bot"
        class="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 text-sm"
      >
        Enable Review Invitations
      </button>
    <% else %>
      <div class="space-y-3">
        <div :for={bot <- @origin_bots} class={"p-3 rounded border #{bot_border_class(bot)}"}>
          <div class="flex items-center justify-between">
            <div class="text-sm">
              <span class="font-mono text-xs text-gray-600">
                {Shortcode.short_code(bot.bot_hash)}
              </span>
              <span class={"ml-2 text-xs font-medium #{bot_status_class(bot)}"}>
                {bot_status_label(bot)}
              </span>
            </div>
            <div class="flex gap-2">
              {render_bot_actions(Map.put(assigns, :bot, bot))}
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp render_bot_actions(assigns) do
    ~H"""
    <%= cond do %>
      <% @bot.deleted_flag -> %>
        <span class="text-xs text-gray-400">Revoked</span>
      <% Worker.running?(@bot.bot_hash) -> %>
        <button
          phx-click="stop_review_bot"
          phx-value-hash={@bot.bot_hash}
          class="px-3 py-1 bg-yellow-600 text-white rounded text-sm hover:bg-yellow-700"
        >
          Stop
        </button>
        <button
          phx-click="revoke_review_bot"
          phx-value-hash={@bot.bot_hash}
          class="px-3 py-1 bg-red-600 text-white rounded text-sm hover:bg-red-700"
        >
          Revoke
        </button>
      <% true -> %>
        <button
          phx-click="start_review_bot"
          phx-value-hash={@bot.bot_hash}
          class="px-3 py-1 bg-blue-600 text-white rounded text-sm hover:bg-blue-700"
        >
          Start
        </button>
        <button
          phx-click="revoke_review_bot"
          phx-value-hash={@bot.bot_hash}
          class="px-3 py-1 bg-red-600 text-white rounded text-sm hover:bg-red-700"
        >
          Revoke
        </button>
    <% end %>
    """
  end

  def decrypt_and_start(bot, origin_crypt_skey) do
    with {:ok, identity} <-
           Identity.unwrap(bot.secret_b64, bot.encrypted_identity_b64, origin_crypt_skey) do
      DynamicSupervisor.start_child(
        Chat.ReviewBot.WorkerSupervisor,
        {Worker, %{bot_hash: bot.bot_hash, origin_hash: bot.origin_hash, identity: identity}}
      )
    end
  end

  def stop(bot_hash) do
    case Worker.whereis(bot_hash) do
      nil -> {:error, :not_running}
      pid -> DynamicSupervisor.terminate_child(Chat.ReviewBot.WorkerSupervisor, pid)
    end
  end

  defp bot_status_label(bot) do
    cond do
      bot.deleted_flag -> "tombstoned"
      Worker.running?(bot.bot_hash) -> "running"
      true -> "configured"
    end
  end

  defp bot_border_class(bot) do
    cond do
      bot.deleted_flag -> "border-red-200 bg-red-50"
      Worker.running?(bot.bot_hash) -> "border-green-200 bg-green-50"
      true -> "border-gray-200"
    end
  end

  defp bot_status_class(bot) do
    cond do
      bot.deleted_flag -> "text-red-600"
      Worker.running?(bot.bot_hash) -> "text-green-600"
      true -> "text-gray-500"
    end
  end
end
