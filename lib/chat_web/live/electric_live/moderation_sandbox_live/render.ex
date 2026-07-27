defmodule ChatWeb.ElectricLive.ModerationSandboxLive.Render do
  @moduledoc "Render functions for the origin moderation sandbox."

  use Phoenix.Component

  alias Chat.Proto.Shortcode

  def render_identity_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 1: Import Origin Identity</h2>
      <p class="text-sm text-gray-600 mb-3">
        Export it from the
        <a href="/electric/origin_sandbox" class="text-blue-600 hover:underline">
          Origin Owner Sandbox
        </a>
        — the moderator authenticates as the origin, never as the owner.
      </p>
      <%= if @identity do %>
        {render_identity_summary(assigns)}
      <% else %>
        <form
          phx-change="validate_key_file"
          phx-submit="import_identity"
          class="flex items-center gap-4"
        >
          <.live_file_input upload={@uploads.key_file} class="text-sm" />
          <button
            type="submit"
            class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 text-sm"
          >
            Import Identity
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  defp render_identity_summary(assigns) do
    ~H"""
    <div class="text-sm space-y-1">
      <p>
        <span class="font-medium">Origin:</span>
        {(@origin && @origin.name) || @identity.name}
        <span class="font-mono text-xs text-gray-500">
          {Shortcode.short_code(@identity.origin_hash)}
        </span>
      </p>
      <p :if={@origin}>
        <span class="font-medium">Moderation mode:</span>
        <span class="font-semibold">{@origin.moderation_mode}</span>
      </p>
      <p :if={@origin && @origin.deleted_flag} class="text-red-600">Origin is soft-deleted</p>
      <p>
        <span class="font-medium">Identity check:</span>
        <%= case @verification do %>
          <% :ok -> %>
            <span class="text-green-700">
              verified against user_cards (signature + KEM round-trip)
            </span>
          <% {:error, reason} -> %>
            <span class="text-red-600">{reason}</span>
          <% _ -> %>
            <span class="text-gray-500">checking...</span>
        <% end %>
      </p>
    </div>
    """
  end

  def render_queue_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-gray-900">Step 2: Moderation Queue</h2>
        <button
          phx-click="refresh"
          disabled={@loading}
          class="px-3 py-1.5 border rounded-lg text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50"
        >
          {if @loading, do: "Loading...", else: "Refresh"}
        </button>
      </div>

      <p :if={@counts} class="text-xs text-gray-500 mb-4 font-mono">
        {@counts.reviews} reviews | {@counts.passwords} password rows | {@counts.post_rights} post rights | {@counts.revoke_rights} revoke rights
      </p>

      <div class="space-y-4">
        <.review_card :for={entry <- @entries} entry={entry} />
      </div>

      <p :if={@entries == [] and not @loading} class="text-sm text-gray-500 py-6 text-center">
        No reviews for this origin yet. Write one in the <a
          href="/electric/review_sandbox"
          class="text-blue-600 hover:underline"
        >Review Sandbox</a>.
      </p>
    </div>
    """
  end

  attr :entry, :map, required: true

  defp review_card(assigns) do
    ~H"""
    <div class="border rounded-lg px-4 py-3">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-3">
          <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{state_class(@entry.state)}"}>
            {state_label(@entry.state)}
          </span>
          <.stars :if={@entry.rating} rating={@entry.rating} />
        </div>
        <span class="text-xs text-gray-400 font-mono">
          {Shortcode.short_code(@entry.author_hash)} | {Shortcode.short_code(@entry.review_hash)}
        </span>
      </div>

      {render_content(assigns)}
      {render_rights(assigns)}
      {render_actions(assigns)}
    </div>
    """
  end

  defp render_content(assigns) do
    ~H"""
    <div class="mb-3">
      <%= case @entry.content_error do %>
        <% :no_password -> %>
          <p class="text-sm text-gray-400 italic">
            Locked — no password available to this origin yet
          </p>
        <% :undecryptable -> %>
          <p class="text-sm text-red-600 italic">
            Content did not decrypt with the available password
          </p>
        <% _ -> %>
          <p :if={@entry.text != ""} class="text-sm text-gray-700">{@entry.text}</p>
          <p :if={@entry.text == ""} class="text-sm text-gray-400 italic">Rating only</p>
      <% end %>
      <p :if={@entry.password_source == :post_right} class="mt-1 text-xs text-blue-600">
        Read via unpublished post right — not visible to the public yet
      </p>
    </div>
    """
  end

  defp render_rights(assigns) do
    ~H"""
    <div class="text-xs font-mono text-gray-500 space-y-0.5 mb-3">
      <p>post right: {right_status(@entry.post_right)}</p>
      <p>revoke right: {right_status(@entry.revoke_right)}</p>
      <p :if={is_nil(@entry.post_right) and is_nil(@entry.revoke_right)} class="text-gray-400">
        no rights — author has not completed the moderation handshake
      </p>
    </div>
    """
  end

  defp render_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <button
        :if={@entry.post_right}
        phx-click="publish"
        phx-value-hash={@entry.review_hash}
        disabled={not publishable?(@entry)}
        class="px-3 py-1.5 rounded-lg text-sm text-white bg-green-600 hover:bg-green-700 disabled:bg-gray-300"
      >
        {if @entry.state == :pending, do: "Publish", else: "Re-publish"}
      </button>
      <button
        :if={@entry.revoke_right}
        phx-click="revoke"
        phx-value-hash={@entry.review_hash}
        disabled={not revocable?(@entry)}
        class="px-3 py-1.5 rounded-lg text-sm text-white bg-red-600 hover:bg-red-700 disabled:bg-gray-300"
      >
        {if @entry.state == :pending, do: "Reject", else: "Revoke"}
      </button>
      <span :if={blocked_note(@entry)} class="text-xs text-amber-700">{blocked_note(@entry)}</span>
    </div>
    """
  end

  attr :rating, :integer, required: true

  defp stars(assigns) do
    ~H"""
    <div class="flex gap-0.5">
      <span :for={i <- 1..5} class={if i <= @rating, do: "text-yellow-400", else: "text-gray-300"}>
        &#9733;
      </span>
    </div>
    """
  end

  # --- Helpers ---

  defp state_label(:public), do: "Public"
  defp state_label(:hidden), do: "Hidden"
  defp state_label(:pending), do: "Pending"

  defp state_class(:public), do: "bg-green-100 text-green-800"
  defp state_class(:hidden), do: "bg-red-100 text-red-800"
  defp state_class(:pending), do: "bg-gray-100 text-gray-800"

  defp right_status(nil), do: "absent"
  defp right_status(%{status: :ok, owner_timestamp: ts}), do: "unwrapped (ts #{ts})"
  defp right_status(%{status: :error, reason: reason}), do: reason

  defp publishable?(%{post_right: %{status: :ok}} = entry),
    do: entry.state != :public and entry.publish_effective?

  defp publishable?(_entry), do: false

  defp revocable?(%{revoke_right: %{status: :ok}} = entry),
    do: entry.state != :hidden and entry.revoke_effective?

  defp revocable?(_entry), do: false

  # Last-Write-Wins by owner_timestamp: an envelope whose timestamp is not above
  # the current latest row would be accepted but change nothing, so surface why
  # the action is disabled rather than letting a moderator submit a no-op.
  defp blocked_note(entry) do
    cond do
      blocked?(entry.post_right, entry.state != :public, entry.publish_effective?) ->
        "publish blocked — right timestamp does not supersede the current row"

      blocked?(entry.revoke_right, entry.state != :hidden, entry.revoke_effective?) ->
        "revoke blocked — right timestamp does not supersede the current row"

      true ->
        nil
    end
  end

  defp blocked?(%{status: :ok}, true, false), do: true
  defp blocked?(_right, _applicable?, _effective?), do: false
end
