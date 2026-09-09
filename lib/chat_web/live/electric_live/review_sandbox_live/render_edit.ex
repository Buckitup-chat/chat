defmodule ChatWeb.ElectricLive.ReviewSandboxLive.RenderEdit do
  @moduledoc "Choosing which of the author's reviews to work on, and editing it."

  use Phoenix.Component

  alias Chat.Proto.Shortcode

  @doc """
  The author's reviews on the selected origin.

  An author may write more than one review per origin, so the list shows all of
  them rather than only the newest. A review whose `review_list` row is missing
  cannot be reopened — its password is gone — but it is still listed, with the
  reason, so a later review does not look as if it had replaced it.
  """
  def render_review_picker(assigns) do
    ~H"""
    <div class="mb-4">
      <h3 class="text-sm font-medium text-gray-700 mb-2">
        Your reviews on this origin ({length(@reviews)})
      </h3>
      <ul class="border rounded-lg divide-y">
        <li
          :for={item <- @reviews}
          class={"flex items-center justify-between gap-3 px-3 py-2 #{if selected?(item, @review), do: "bg-green-50"}"}
        >
          <div class="min-w-0">
            <span class="font-mono text-xs text-gray-500">
              {Shortcode.short_code(item.review_hash)}
            </span>
            <span :if={item.review} class="ml-2 text-yellow-400">{stars(item.review.rating)}</span>
            <span :if={item.review && item.review.text != ""} class="ml-2 text-sm text-gray-700">
              {item.review.text}
            </span>
            <p :if={item.error} class="text-xs text-gray-500 italic">{item.error}</p>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <span class="text-xs text-gray-400">{item.owner_timestamp}</span>
            <span :if={selected?(item, @review)} class="text-xs font-medium text-green-700">
              open
            </span>
            <button
              :if={item.review && not selected?(item, @review)}
              phx-click="select_review"
              phx-value-hash={item.review_hash}
              class="text-xs px-3 py-1 border rounded-lg text-blue-600 hover:bg-blue-50"
            >
              Open
            </button>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  defp selected?(_item, nil), do: false
  defp selected?(item, review), do: item.review_hash == review.review_hash

  defp stars(rating), do: String.duplicate("★", rating) <> String.duplicate("☆", 5 - rating)

  @doc "Controls under a submitted review, with pre-moderation's edit lock applied."
  def render_review_actions(assigns) do
    ~H"""
    <div class="mt-3 flex gap-2 items-center">
      <button
        :if={not edit_locked?(assigns)}
        phx-click="start_edit"
        class="px-4 py-2 bg-amber-500 text-white rounded-lg text-sm hover:bg-amber-600"
      >
        Edit Review
      </button>
      <p :if={edit_locked?(assigns)} class="text-sm text-gray-600">
        Locked — the origin has moderated this version, so it can no longer be edited.
      </p>
      <button
        phx-click="new_review"
        class="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg text-sm hover:bg-gray-300"
      >
        New Review
      </button>
    </div>
    """
  end

  # Mirrors `Chat.Data.Review.Validation.validate_edit_allowed/2`: pre mode locks a
  # review once a review_public_passwords row exists for it. The shape only reports
  # what it has seen, so this hides a doomed button — the server stays the authority.
  defp edit_locked?(%{moderation_mode: :pre, observed_proofs: %{} = proofs}),
    do: not is_nil(proofs[:review_password_sign_hash])

  defp edit_locked?(_assigns), do: false

  def render_edit_form(assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-sm text-gray-600">
        Editing review
        <span class="font-mono text-xs">{Shortcode.short_code(@review.review_hash)}</span>
        — old version will be archived.
      </p>
      <form phx-submit="submit_edit" phx-change="edit_form_changed" class="space-y-3">
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
          >{@edit_text}</textarea>
        </div>
        <div class="flex gap-2">
          <button
            type="submit"
            disabled={@selected_rating == 0}
            class={"bg-green-600 text-white px-4 py-2 rounded-lg text-sm #{if @selected_rating == 0, do: "opacity-50 cursor-not-allowed", else: "hover:bg-green-700"}"}
          >
            Save Edit
          </button>
          <button
            type="button"
            phx-click="cancel_edit"
            class="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg text-sm hover:bg-gray-300"
          >
            Cancel
          </button>
        </div>
      </form>
    </div>
    """
  end
end
