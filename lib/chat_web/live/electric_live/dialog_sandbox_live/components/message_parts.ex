defmodule ChatWeb.ElectricLive.DialogSandboxLive.Components.MessageParts do
  @moduledoc false

  use Phoenix.Component

  alias Chat.Proto.Shortcode
  alias ChatWeb.ElectricLive.DialogSandboxLive.ContentComponents

  @emojis ~w(👍 ❤️ 😂 😮 😢 🎉)

  def reaction_display(%{reactions: []} = assigns), do: ~H""

  def reaction_display(assigns) do
    assigns = assign(assigns, :grouped, Enum.frequencies_by(assigns.reactions, & &1.emoji))

    ~H"""
    <div class="flex flex-wrap gap-1 mt-1">
      <%= for {emoji, count} <- @grouped do %>
        <span class="inline-flex items-center gap-0.5 px-1.5 py-0.5 bg-gray-100 rounded-full text-xs">
          <span>{emoji}</span>
          <%= if count > 1 do %>
            <span class="text-gray-500">{count}</span>
          <% end %>
        </span>
      <% end %>
    </div>
    """
  end

  def version_history(%{versions: []} = assigns) do
    ~H"""
    <div class="mt-2 pl-3 border-l-2 border-gray-300 text-xs text-gray-400 italic">
      Loading...
    </div>
    """
  end

  def version_history(assigns) do
    ~H"""
    <div class="mt-2 pl-3 border-l-2 border-gray-300 space-y-1">
      <%= for v <- @versions do %>
        <div class="text-xs text-gray-500">
          <span class="text-gray-400">{format_timestamp(v.owner_timestamp)}</span>
          <span class="ml-1">
            <ContentComponents.render_content
              content={v.content}
              message_id={"#{v.message_id}-v#{v.sign_hash}"}
              deleted={v.deleted}
            />
          </span>
          <.reaction_display reactions={Map.get(@reactions, v.sign_hash, [])} />
        </div>
      <% end %>
    </div>
    """
  end

  def emoji_buttons(assigns) do
    assigns = assign(assigns, :emojis, @emojis)

    ~H"""
    <div class="flex gap-0.5 mt-1">
      <%= for emoji <- @emojis do %>
        <button
          phx-click="react"
          phx-value-message_id={@message_id}
          phx-value-sign_hash={@sign_hash}
          phx-value-emoji={emoji}
          class="px-1 py-0.5 hover:bg-gray-200 rounded text-sm cursor-pointer"
          title={"React with #{emoji}"}
        >
          {emoji}
        </button>
      <% end %>
    </div>
    """
  end

  def edit_form(assigns) do
    ~H"""
    <form phx-submit="save_edit" class="flex gap-2">
      <input type="hidden" name="message_id" value={@message_id} />
      <input
        type="text"
        name="text"
        value={@current_content}
        class="flex-1 px-2 py-1 border rounded text-sm"
        autocomplete="off"
        autofocus
      />
      <button type="submit" class="px-2 py-1 bg-green-600 text-white rounded text-xs font-medium">
        Save
      </button>
      <button
        type="button"
        phx-click="cancel_edit"
        class="px-2 py-1 bg-gray-300 text-gray-700 rounded text-xs"
      >
        Cancel
      </button>
    </form>
    """
  end

  def message_actions(assigns) do
    ~H"""
    <div class="flex gap-1">
      <button
        phx-click="start_edit"
        phx-value-message_id={@message_id}
        class="text-[10px] px-1.5 py-0.5 bg-gray-100 hover:bg-gray-200 rounded text-gray-600"
      >
        Edit
      </button>
      <button
        phx-click="delete_message"
        phx-value-message_id={@message_id}
        class="text-[10px] px-1.5 py-0.5 bg-red-50 hover:bg-red-100 rounded text-red-600"
        data-confirm="Delete this message?"
      >
        Delete
      </button>
    </div>
    """
  end

  def receipt_status(%{receipts: []} = assigns) do
    ~H"""
    <span class="text-xs text-gray-400">✓ sent</span>
    """
  end

  def receipt_status(assigns) do
    assigns = assign(assigns, :has_read, Enum.any?(assigns.receipts, &(&1.type == "read")))

    ~H"""
    <span class={
      "text-xs #{if @has_read, do: "text-blue-500 font-medium", else: "text-green-600"}"
    }>
      {if @has_read, do: "✓✓ read", else: "✓✓ delivered"}
    </span>
    """
  end

  def receipt_buttons(assigns) do
    assigns =
      assign(
        assigns,
        :already_sent,
        assigns.receipts
        |> Enum.filter(&(&1.peer_hash == assigns.user_hash))
        |> Enum.map(& &1.type)
        |> MapSet.new()
      )

    ~H"""
    <div class="flex gap-1">
      <%= unless "delivered" in @already_sent do %>
        <button
          phx-click="send_receipt"
          phx-value-message_id={@message_id}
          phx-value-sign_hash={@sign_hash}
          phx-value-type="delivered"
          class="text-[10px] px-1.5 py-0.5 bg-gray-100 hover:bg-gray-200 rounded text-gray-600"
        >
          ✓ Delivered
        </button>
      <% end %>
      <%= unless "read" in @already_sent do %>
        <button
          phx-click="send_receipt"
          phx-value-message_id={@message_id}
          phx-value-sign_hash={@sign_hash}
          phx-value-type="read"
          class="text-[10px] px-1.5 py-0.5 bg-blue-50 hover:bg-blue-100 rounded text-blue-600"
        >
          ✓✓ Read
        </button>
      <% end %>
    </div>
    """
  end

  def refs_list(%{refs_map: refs} = assigns) when map_size(refs) == 0 do
    ~H""
  end

  def refs_list(assigns) do
    ~H"""
    <div class="mt-1 flex flex-wrap gap-1">
      <span class="text-[10px] text-gray-400">refs:</span>
      <%= for {msg_id, sign_hash} <- @refs_map do %>
        <span class="relative group">
          <span class="text-[10px] font-mono text-indigo-500 cursor-default">
            {Shortcode.short_code(msg_id)}
          </span>
          <span class="absolute bottom-full left-0 mb-1 px-2 py-1 bg-gray-900 text-white text-[10px] font-mono rounded whitespace-nowrap invisible group-hover:visible z-10">
            {sign_hash}
          </span>
        </span>
      <% end %>
    </div>
    """
  end

  def sync_badge(%{status: :loading} = assigns) do
    ~H"""
    <span class="text-xs text-yellow-600 animate-pulse">Syncing...</span>
    """
  end

  def sync_badge(%{status: :loaded} = assigns) do
    ~H"""
    <span class="text-xs text-green-600">Synced</span>
    """
  end

  def sync_badge(%{status: :live} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 text-xs text-green-700">
      <span class="w-2 h-2 rounded-full bg-green-500 animate-pulse"></span> Live
    </span>
    """
  end

  def sync_badge(assigns) do
    ~H"""
    <span class="text-xs text-gray-500">Idle</span>
    """
  end

  def format_timestamp(ts) when is_number(ts) do
    ts
    |> DateTime.from_unix!()
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  def format_timestamp(ts) when is_binary(ts) do
    case Integer.parse(ts) do
      {n, ""} -> format_timestamp(n)
      _ -> ts
    end
  end

  def format_timestamp(ts), do: inspect(ts)

  def unwrap_for_edit(nil), do: ""

  def unwrap_for_edit(json) do
    case Jason.decode(json) do
      {:ok, string} when is_binary(string) -> string
      _ -> json
    end
  end
end
