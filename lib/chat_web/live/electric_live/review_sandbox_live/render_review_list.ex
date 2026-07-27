defmodule ChatWeb.ElectricLive.ReviewSandboxLive.RenderReviewList do
  @moduledoc false

  use Phoenix.Component

  alias Chat.Proto.Shortcode
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ReviewList.Proofs

  def render_review_list_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 mb-4">Step 5: Add to Review List</h2>
      <p class="text-sm text-gray-600 mb-3">
        Share this review with your contacts, independent of moderation state.
      </p>
      {render_proofs(assigns)}
      {render_submit(assigns)}
      <%= if @review_list.entry do %>
        {render_key_delivery(assigns)}
      <% end %>
    </div>
    """
  end

  defp render_proofs(assigns) do
    ~H"""
    <div class="mb-4">
      <div class="flex items-center justify-between mb-2">
        <h3 class="text-sm font-medium text-gray-700">Moderation proofs</h3>
        <button
          phx-click="load_review_list_proofs"
          class="text-xs px-3 py-1 border rounded-lg text-blue-600 hover:bg-blue-50"
        >
          {if @observed_proofs, do: "Refresh", else: "Load proofs"}
        </button>
      </div>
      <table class="w-full text-xs">
        <thead class="text-gray-500 text-left">
          <tr>
            <th class="py-1">Proof</th>
            <th>Required</th>
            <th>Signed by you</th>
            <th>Seen in shape</th>
            <th>Verdict</th>
          </tr>
        </thead>
        <tbody class="font-mono">
          <tr :for={slot <- Proofs.slots()} class="border-t">
            <td class="py-1">{slot_label(slot)}</td>
            <td class="text-gray-500">{Proofs.requirement(@moderation_mode, slot)}</td>
            <td>{short(@proof_hashes[slot])}</td>
            <td>{short(@observed_proofs && @observed_proofs[slot])}</td>
            <td class={verdict_class(verdict(assigns, slot))}>{verdict(assigns, slot)}</td>
          </tr>
        </tbody>
      </table>
      <p :if={mismatch?(assigns)} class="mt-2 text-xs font-medium text-red-700">
        A promoted row differs from what you signed — submission blocked.
      </p>
    </div>
    """
  end

  defp render_submit(assigns) do
    ~H"""
    <div class="text-sm">
      <%= cond do %>
        <% is_nil(@review_list.entry) -> %>
          <button
            phx-click="submit_review_list"
            disabled={not submittable?(assigns)}
            class={"px-4 py-2 rounded-lg text-sm text-white #{if submittable?(assigns), do: "bg-green-600 hover:bg-green-700", else: "bg-gray-400 cursor-not-allowed"}"}
          >
            Add to Review List
          </button>
        <% awaiting_approval?(assigns) -> %>
          <p class="text-gray-600 mb-2">
            Row added without a promotion proof — pre-moderation, so the origin has not published yet.
          </p>
          <button
            phx-click="fill_password_proof"
            disabled={not password_published?(assigns)}
            class={"px-4 py-2 rounded-lg text-sm text-white #{if password_published?(assigns), do: "bg-green-600 hover:bg-green-700", else: "bg-gray-400 cursor-not-allowed"}"}
          >
            {if password_published?(assigns),
              do: "Fill promotion proof",
              else: "Waiting for origin to publish"}
          </button>
        <% true -> %>
          <p class="font-medium text-green-700">
            Review list row complete — contacts holding your review_list_password can read this review.
          </p>
      <% end %>
    </div>
    """
  end

  defp render_key_delivery(assigns) do
    ~H"""
    <div class="mt-5 pt-4 border-t">
      <h3 class="text-sm font-medium text-gray-700 mb-1">Share the list key</h3>
      <p class="text-xs text-gray-500 mb-3">
        Sends <code>review_list_key</code> as a dialog message. One key opens every review you write.
      </p>
      <form phx-change="select_contacts" phx-submit="send_list_key" class="space-y-2">
        <label :for={peer <- @peers} class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="contacts[]"
            value={peer.user_hash}
            checked={peer.user_hash in @selected_contacts}
          />
          <span>{peer.name}</span>
          <span class="font-mono text-xs text-gray-400">{short(peer.user_hash)}</span>
          <span :if={peer.user_hash in @key_sent_to} class="text-xs text-green-700">sent</span>
        </label>
        <p :if={@peers == []} class="text-sm text-gray-500">No other users to share with.</p>
        <button
          type="submit"
          disabled={@selected_contacts == []}
          class={"mt-2 px-4 py-2 rounded-lg text-sm text-white #{if @selected_contacts == [], do: "bg-gray-400 cursor-not-allowed", else: "bg-blue-600 hover:bg-blue-700"}"}
        >
          Send list key
        </button>
      </form>
    </div>
    """
  end

  # --- Helpers ---

  defp verdict(assigns, slot), do: proof_status(assigns)[slot]

  defp proof_status(%{observed_proofs: nil}), do: %{}

  defp proof_status(assigns),
    do: Proofs.status(assigns.moderation_mode, assigns.observed_proofs, assigns.proof_hashes)

  defp submittable?(%{observed_proofs: nil}), do: false
  defp submittable?(assigns), do: assigns |> proof_status() |> Proofs.submittable?()

  defp password_published?(%{observed_proofs: nil}), do: false
  defp password_published?(assigns), do: assigns |> proof_status() |> Proofs.password_published?()

  defp mismatch?(assigns), do: assigns |> proof_status() |> Enum.any?(&(elem(&1, 1) == :mismatch))

  defp awaiting_approval?(%{moderation_mode: :pre, review_list: %{entry: entry}})
       when not is_nil(entry),
       do: is_nil(entry.review_password_sign_hash)

  defp awaiting_approval?(_assigns), do: false

  defp slot_label(:review_password_sign_hash), do: "promotion"
  defp slot_label(:post_right_sign_hash), do: "post right"
  defp slot_label(:revoke_right_sign_hash), do: "revoke right"

  defp verdict_class(:mismatch), do: "text-red-700 font-semibold"
  defp verdict_class(:missing), do: "text-red-700"
  defp verdict_class(:ok), do: "text-green-700"
  defp verdict_class(_verdict), do: "text-gray-500"

  defp short(nil), do: "—"
  defp short(hash), do: Shortcode.short_code(hash)
end
