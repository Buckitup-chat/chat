defmodule ChatWeb.ElectricLive.ReviewSandboxLive.Render do
  @moduledoc false

  use Phoenix.Component

  import ChatWeb.ElectricLive.RequestLog
  import ChatWeb.ElectricLive.ReviewSandboxLive.RenderReviewList
  import ChatWeb.ElectricLive.ReviewSandboxLive.RenderVerification

  alias Chat.Proto.Shortcode

  def render_page(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-4xl mx-auto px-4">
        <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
          &larr; Electric Index
        </a>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Review Author Sandbox</h1>
        <p class="text-sm text-gray-600 mb-6">
          Test review submission, moderation pipeline, and review list via Electric API
        </p>

        <%= if @error_message do %>
          <div class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded flex justify-between">
            <span>{@error_message}</span>
            <button phx-click="clear_error" class="text-red-600 hover:text-red-800">x</button>
          </div>
        <% end %>

        <div class="space-y-6">
          {render_author_section(assigns)}
          <%= if @author do %>
            {render_review_section(assigns)}
          <% end %>
          <%= if @review do %>
            {render_rights_section(assigns)}
          <% end %>
          <%= if @rights_submitted and @moderation_mode not in [:none, nil] do %>
            {render_sign_section(assigns)}
          <% end %>
          <%= if rights_complete?(assigns) do %>
            {render_review_list_section(assigns)}
          <% end %>
          {render_log_section(assigns)}
        </div>
      </div>
    </div>
    """
  end

  def render_author_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 1: Import Author Identity</h2>
      <p class="text-sm text-gray-600 mb-3">
        Export keys from
        <a href="/electric/user_sandbox" class="text-blue-600 hover:underline">User Sandbox</a>
        , then import here.
      </p>
      <%= if @author do %>
        <div class="text-sm">
          <span class="font-medium text-green-700">Identity loaded:</span>
          <span class="font-mono text-xs text-gray-600">
            {Shortcode.short_code(@author.user_hash)}
          </span>
          <span class="text-gray-500">({@author.name})</span>
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

  def render_review_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 2: Submit Review</h2>
      <%= if @review do %>
        <div class="text-sm space-y-1">
          <p>
            <span class="font-medium">Review hash:</span>
            <span class="font-mono text-xs">{Shortcode.short_code(@review.review_hash)}</span>
          </p>
          <p>
            <span class="font-medium">Origin:</span>
            <span class="font-mono text-xs">{Shortcode.short_code(@review.origin_hash)}</span>
          </p>
          <p>
            <span class="font-medium">Rating:</span>
            <span class="text-yellow-400">{String.duplicate("★", @review.rating)}</span>
            <span class="text-gray-300">{String.duplicate("★", 5 - @review.rating)}</span>
          </p>
          <%= if @review.text != "" do %>
            <p><span class="font-medium">Text:</span> {@review.text}</p>
          <% end %>
          <p><span class="font-medium">Timestamp:</span> {@review.owner_timestamp}</p>
          <details class="mt-2">
            <summary class="cursor-pointer text-xs text-gray-500">
              Content JSON (plaintext before encryption)
            </summary>
            <pre class="mt-1 text-xs font-mono bg-gray-50 p-2 rounded overflow-x-auto">{@review.content_json}</pre>
          </details>
        </div>
      <% else %>
        <form phx-submit="submit_review" phx-change="form_changed" class="space-y-3">
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Origin</label>
            <select name="origin_hash" required class="w-full px-3 py-2 border rounded-lg text-sm">
              <option value="">Select an origin...</option>
              <option
                :for={origin <- @origins}
                value={origin.origin_hash}
                selected={origin.origin_hash == @origin_hash}
              >
                {origin.name}
              </option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Rating</label>
            <div class="flex gap-1">
              <button
                :for={n <- 1..5}
                type="button"
                phx-click="set_rating"
                phx-value-rating={n}
                class="text-2xl focus:outline-none"
              >
                <span class={if n <= @selected_rating, do: "text-yellow-400", else: "text-gray-300"}>
                  ★
                </span>
              </button>
            </div>
            <input type="hidden" name="rating" value={@selected_rating} />
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">
              Review text <span class="text-gray-400">(optional)</span>
            </label>
            <textarea
              name="content"
              rows="3"
              class="w-full px-3 py-2 border rounded-lg text-sm"
              placeholder="Write your review..."
            ></textarea>
          </div>
          <button
            type="submit"
            disabled={@selected_rating == 0}
            class={"bg-green-600 text-white px-4 py-2 rounded-lg text-sm #{if @selected_rating == 0, do: "opacity-50 cursor-not-allowed", else: "hover:bg-green-700"}"}
          >
            Submit Review
          </button>
        </form>
      <% end %>
    </div>
    """
  end

  def render_rights_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 3: Submit Rights</h2>
      <p class="text-sm text-gray-600 mb-3">
        Submit password candidates for moderation pipeline.
        Mode: <span class="font-semibold text-indigo-600">{@moderation_mode || "unknown"}</span>
      </p>
      <%= if @rights_submitted do %>
        <div class="text-sm space-y-1">
          <p class="font-medium text-green-700">Password candidates submitted.</p>
          <%= case @moderation_mode do %>
            <% :none -> %>
              <p class="text-gray-600">Auto-promoted — review password is now public.</p>
            <% :post -> %>
              <p class="text-gray-600">Revoke right candidate created. Proceed to signing.</p>
            <% :pre -> %>
              <p class="text-gray-600">
                Post and revoke right candidates created. Proceed to signing.
              </p>
            <% _ -> %>
              <p class="text-gray-600">Candidates submitted.</p>
          <% end %>
        </div>
      <% else %>
        <button
          phx-click="submit_rights"
          class="bg-blue-600 text-white px-4 py-2 rounded-lg text-sm hover:bg-blue-700"
        >
          Submit Password Candidates
        </button>
      <% end %>
    </div>
    """
  end

  def render_sign_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 4: Sign Right Candidates</h2>
      <%= if @rights_signed do %>
        <div class="text-sm space-y-1">
          <p class="font-medium text-green-700">Right candidates signed and promoted.</p>
          <%= if @moderation_mode == :post do %>
            <p class="text-gray-600">Revoke right created. Review password published.</p>
          <% else %>
            <p class="text-gray-600">
              Post and revoke rights created. Password pending origin approval.
            </p>
          <% end %>
        </div>
      <% else %>
        <div class="text-sm space-y-2 mb-3">
          <p class="text-gray-600">Unsigned right candidates from server:</p>
          <%= if @right_candidates.revoke do %>
            <div class="bg-gray-50 p-2 rounded text-xs font-mono">
              <span class="font-semibold">Revoke:</span>
              {Shortcode.short_code(@right_candidates.revoke.review_hash)}
              <span class="text-gray-400 ml-2">ts={@right_candidates.revoke.owner_timestamp}</span>
            </div>
          <% end %>
          <%= if @right_candidates.post do %>
            <div class="bg-gray-50 p-2 rounded text-xs font-mono">
              <span class="font-semibold">Post:</span>
              {Shortcode.short_code(@right_candidates.post.review_hash)}
              <span class="text-gray-400 ml-2">ts={@right_candidates.post.owner_timestamp}</span>
            </div>
          <% end %>
        </div>

        <%= if @verification do %>
          {render_verification_results(assigns)}

          <%= if @verification.all_ok do %>
            <button
              phx-click="sign_rights"
              class="mt-3 bg-green-600 text-white px-4 py-2 rounded-lg text-sm hover:bg-green-700"
            >
              Sign & Submit
            </button>
          <% else %>
            <p class="mt-3 text-sm font-medium text-red-700">
              Verification failed — signing blocked.
            </p>
          <% end %>
        <% else %>
          <button
            phx-click="verify_wrapping"
            class="bg-blue-600 text-white px-4 py-2 rounded-lg text-sm hover:bg-blue-700"
          >
            Verify Wrapping
          </button>
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc "Whether the moderation pipeline is far enough along to build a review_list row."
  def rights_complete?(assigns) do
    cond do
      not assigns.rights_submitted -> false
      assigns.moderation_mode == :none -> true
      assigns.rights_signed -> true
      true -> false
    end
  end
end
