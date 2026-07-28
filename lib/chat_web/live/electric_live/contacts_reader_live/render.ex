defmodule ChatWeb.ElectricLive.ContactsReaderLive.Render do
  @moduledoc false

  use Phoenix.Component

  import ChatWeb.ElectricLive.RequestLog

  alias Chat.Proto.Shortcode

  def render_page(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-4xl mx-auto px-4">
        <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
          &larr; Electric Index
        </a>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Contacts Review Reader</h1>
        <p class="text-sm text-gray-600 mb-6">
          Read your own reviews and contacts' reviews via review_list + review_list_password
        </p>

        <div
          :if={@error_message}
          class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded flex justify-between"
        >
          <span>{@error_message}</span>
          <button phx-click="clear_error" class="text-red-600 hover:text-red-800">x</button>
        </div>

        <div class="space-y-6">
          {render_identity_section(assigns)}
          <%= if @user do %>
            {render_contacts_section(assigns)}
          <% end %>
          <%= if @selected_source do %>
            {render_reviews_section(assigns)}
          <% end %>
          {render_log_section(assigns)}
        </div>
      </div>
    </div>
    """
  end

  defp render_identity_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 1: Import Reader Identity</h2>
      <p class="text-sm text-gray-600 mb-3">
        Export keys from
        <a href="/electric/user_sandbox" class="text-blue-600 hover:underline">User Sandbox</a>
        , then import here.
      </p>
      <%= if @user do %>
        <div class="text-sm space-y-1">
          <p>
            <span class="font-medium text-green-700">Identity loaded:</span>
            <span class="font-mono text-xs text-gray-600">
              {Shortcode.short_code(@user.user_hash)}
            </span>
            <span class="text-gray-500">({@user.name})</span>
          </p>
          <p :if={@own_key} class="text-xs text-gray-500">
            Own review_list_password available — can read own review_list
          </p>
        </div>
      <% else %>
        <form phx-change="validate_key_file" phx-submit="import_keys" class="flex items-center gap-4">
          <.live_file_input upload={@uploads.key_file} class="text-sm" />
          <button
            type="submit"
            class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 text-sm"
          >
            Import Keys
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  defp render_contacts_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 2: Discover Contacts</h2>
      <p class="text-sm text-gray-600 mb-3">
        Scan dialogs for <code class="bg-gray-100 px-1 rounded">review_list_key</code>
        messages from peers.
      </p>

      <button
        phx-click="scan_dialogs"
        class="bg-blue-600 text-white px-4 py-2 rounded-lg text-sm hover:bg-blue-700 mb-4"
      >
        Scan Dialogs
      </button>

      <div class="space-y-2">
        <button
          :if={@own_key}
          phx-click="select_source"
          phx-value-source="own"
          class={"block w-full text-left px-4 py-3 rounded-lg border text-sm #{if @selected_source == "own", do: "border-blue-500 bg-blue-50", else: "border-gray-200 hover:bg-gray-50"}"}
        >
          <span class="font-medium text-gray-900">My reviews</span>
          <span class="text-xs text-gray-500 ml-2">
            {Shortcode.short_code(@user.user_hash)}
          </span>
        </button>
        <button
          :for={{peer_hash, _key} <- @contacts}
          phx-click="select_source"
          phx-value-source={peer_hash}
          class={"block w-full text-left px-4 py-3 rounded-lg border text-sm #{if @selected_source == peer_hash, do: "border-blue-500 bg-blue-50", else: "border-gray-200 hover:bg-gray-50"}"}
        >
          <span class="font-medium text-gray-900">Contact</span>
          <span class="font-mono text-xs text-gray-600 ml-2">
            {Shortcode.short_code(peer_hash)}
          </span>
        </button>
        <p :if={@contacts == %{} and @own_key == nil} class="text-sm text-gray-500">
          No review_list_key messages found. Ask a contact to share from the
          <a href="/electric/review_sandbox" class="text-blue-600 hover:underline">
            Review Sandbox
          </a>
          .
        </p>
      </div>
    </div>
    """
  end

  defp render_reviews_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">
        Step 3: Reviews
        <span class="text-sm font-normal text-gray-500">
          for {source_label(@selected_source, @user)}
        </span>
      </h2>

      <%= if @loading do %>
        <div class="flex items-center gap-2 text-sm text-gray-600">
          <div class="animate-spin h-4 w-4 border-2 border-blue-600 border-t-transparent rounded-full">
          </div>
          Loading...
        </div>
      <% else %>
        <div :if={@review_list_entries != []} class="mb-3 text-xs text-gray-500">
          {length(@review_list_entries)} review_list entries, {length(@decrypted_reviews)} decrypted
        </div>

        <div class="space-y-4">
          <div
            :for={review <- @decrypted_reviews}
            class={"rounded-lg px-5 py-4 #{review_card_class(review_visibility(review, @public_passwords))}"}
          >
            <div class="flex items-center justify-between mb-2">
              <.stars rating={review.rating} />
              <div class="text-xs text-right space-y-0.5">
                <p class="font-mono text-gray-400">
                  {Shortcode.short_code(review.author_hash)}
                </p>
                <p><.visibility_badge status={review_visibility(review, @public_passwords)} /></p>
              </div>
            </div>
            <p :if={review.text != ""} class="text-sm text-gray-700">{review.text}</p>
            <p :if={review.text == ""} class="text-sm text-gray-400 italic">Rating only</p>
            <p class="mt-2 text-xs text-gray-400">
              Origin: <span class="font-mono">{Shortcode.short_code(review.origin_hash)}</span>
            </p>
          </div>
        </div>
        <p :if={@decrypted_reviews == [] and @review_list_entries != []} class="text-sm text-gray-500">
          review_list entries found but no reviews could be decrypted.
        </p>
        <p :if={@decrypted_reviews == [] and @review_list_entries == []} class="text-sm text-gray-500">
          No reviews found.
        </p>
      <% end %>
    </div>
    """
  end

  defp source_label("own", user), do: "#{user.name} (own)"
  defp source_label(hash, _user), do: Shortcode.short_code(hash)

  defp review_visibility(review, public_passwords) do
    case Map.get(public_passwords, review.review_hash) do
      true -> :public
      false -> :hidden
      nil -> :contacts_only
    end
  end

  defp review_card_class(:public), do: "bg-white shadow"
  defp review_card_class(:hidden), do: "bg-amber-50 border border-amber-200"
  defp review_card_class(:contacts_only), do: "bg-purple-50 border border-purple-200"

  attr :status, :atom, required: true

  defp visibility_badge(%{status: status} = assigns) do
    {text, color} =
      case status do
        :public -> {"public", "bg-green-100 text-green-800"}
        :hidden -> {"hidden", "bg-amber-100 text-amber-800"}
        :contacts_only -> {"contacts only", "bg-purple-100 text-purple-800"}
      end

    assigns = assign(assigns, text: text, color: color)

    ~H"""
    <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{@color}"}>
      {@text}
    </span>
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
end
