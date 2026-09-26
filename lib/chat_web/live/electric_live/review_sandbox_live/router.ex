defmodule ChatWeb.ElectricLive.ReviewSandboxLive.Router do
  @moduledoc "Event handlers for the Review Author Sandbox LiveView."

  import ChatWeb.ElectricLive.ReviewSandboxLive.State
  import ChatWeb.LiveHelpers, only: [public_url: 1]
  import Phoenix.Component
  import Phoenix.LiveView, only: [consume_uploaded_entries: 3]

  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.IdentityCheck
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ApiClient
  alias ChatWeb.ElectricLive.ReviewSandboxLive.Contacts
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ReviewList
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ReviewLoader
  alias ChatWeb.ElectricLive.ReviewSandboxLive.Verification

  # --- Step 1: identity ---

  def handle_event("validate_key_file", _params, socket), do: {:noreply, socket}

  def handle_event("import_keys", _params, socket) do
    [result] =
      consume_uploaded_entries(socket, :key_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case Crypto.parse_and_validate_identity(result) do
      {:ok, user_data} ->
        user_data
        |> IdentityCheck.mark_on_server(public_url(socket))
        |> then(&load_author(socket, &1))
        |> noreply()

      {:error, reason} ->
        socket |> assign(error_message: "Import failed: #{reason}") |> noreply()
    end
  end

  # --- Step 2: write or edit the review ---

  # Fires on every keystroke in the review text, so the shape read that looks for
  # an already-written review is gated on the origin actually changing.
  def handle_event("form_changed", %{"origin_hash" => raw_hash}, socket) do
    origin_hash = if raw_hash == "", do: nil, else: raw_hash

    case socket.assigns.origin_hash do
      ^origin_hash -> noreply(socket)
      _other -> socket |> select_origin(origin_hash) |> noreply()
    end
  end

  def handle_event("new_review", _params, socket) do
    socket |> reset_review() |> assign(selected_rating: 0, edit_text: "") |> noreply()
  end

  def handle_event("select_review", %{"hash" => review_hash}, socket) do
    socket |> select_review(review_hash) |> noreply()
  end

  def handle_event("set_rating", %{"rating" => rating}, socket) do
    socket |> assign(selected_rating: String.to_integer(rating)) |> noreply()
  end

  def handle_event("submit_review", %{"origin_hash" => origin_hash} = params, socket) do
    rating = params |> Map.fetch!("rating") |> String.to_integer()
    text = Map.get(params, "content", "")

    case ApiClient.submit_review(socket.assigns.author, origin_hash, rating, text, url(socket)) do
      {:ok, %{review: review, log_entries: logs}} ->
        socket
        |> assign(origin_hash: origin_hash)
        |> add_review(review)
        |> append_logs(logs)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs) |> noreply()
    end
  end

  def handle_event("start_edit", _params, socket) do
    %{review: review} = socket.assigns

    socket
    |> assign(editing: true, selected_rating: review.rating, edit_text: review.text)
    |> noreply()
  end

  def handle_event("edit_form_changed", params, socket) do
    socket |> assign(edit_text: Map.get(params, "content", "")) |> noreply()
  end

  def handle_event("cancel_edit", _params, socket) do
    socket |> assign(editing: false) |> noreply()
  end

  # Nothing downstream is invalidated by an edit: the new content is re-encrypted
  # under the same review_password, so the promoted password, the rights and the
  # review_list row all still hold. Only the review's tip moves.
  def handle_event("submit_edit", %{"rating" => raw_rating} = params, socket) do
    %{author: author, review: review} = socket.assigns
    rating = String.to_integer(raw_rating)
    text = Map.get(params, "content", "")

    case concurrent_edit(review, url(socket)) do
      nil -> socket |> apply_edit(author, review, rating, text) |> noreply()
      reason -> socket |> assign(error_message: reason) |> noreply()
    end
  end

  # --- Steps 3-4: moderation pipeline ---

  def handle_event("submit_rights", _params, socket) do
    %{author: author, review: review} = socket.assigns

    case ApiClient.submit_password_candidates(author, review, url(socket)) do
      {:ok, %{candidates: candidates, shared_secrets: secrets} = result} ->
        socket
        |> assign(rights_submitted: true, right_candidates: candidates, shared_secrets: secrets)
        |> capture_proof_hashes(result)
        |> append_logs(result.log_entries)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs) |> noreply()
    end
  end

  def handle_event("verify_wrapping", _params, socket) do
    {author, candidates, secrets, review} = moderation_assigns(socket)
    verification = Verification.verify_candidates(candidates, secrets, review, author)
    socket |> assign(verification: verification) |> noreply()
  end

  def handle_event("sign_rights", _params, socket) do
    {author, candidates, secrets, review} = moderation_assigns(socket)

    case ApiClient.sign_right_candidates(author, candidates, secrets, review, url(socket)) do
      {:ok, result} ->
        socket
        |> assign(rights_signed: true)
        |> capture_proof_hashes(result)
        |> append_logs(result.log_entries)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs) |> noreply()
    end
  end

  # --- Step 5: review list ---

  def handle_event("load_review_list_proofs", _params, socket) do
    observed = ReviewList.load_proofs(socket.assigns.review, url(socket))
    socket |> assign(observed_proofs: observed) |> adopt_proofs(observed) |> noreply()
  end

  def handle_event("submit_review_list", _params, socket) do
    %{author: author, review: review, moderation_mode: mode, proof_hashes: local} = socket.assigns
    status = ReviewList.proof_status(mode, socket.assigns.observed_proofs, local)
    fields = ReviewList.proof_fields(mode, local, status)

    case ReviewList.submit_entry(author, review, local, fields, url(socket)) do
      {:ok, %{entry: entry, log_entries: logs}} ->
        socket
        |> assign(review_list: %{entry: entry})
        |> load_peers()
        |> append_logs(logs)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs) |> noreply()
    end
  end

  def handle_event("fill_password_proof", _params, socket) do
    %{author: author, review_list: %{entry: entry}, proof_hashes: local} = socket.assigns
    password_hash = local[:review_password_sign_hash]

    case ReviewList.fill_password_proof(author, entry, password_hash, url(socket)) do
      {:ok, %{entry: filled, log_entries: logs}} ->
        socket |> assign(review_list: %{entry: filled}) |> append_logs(logs) |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs) |> noreply()
    end
  end

  def handle_event("select_contacts", params, socket) do
    socket |> assign(selected_contacts: Map.get(params, "contacts", [])) |> noreply()
  end

  def handle_event("send_list_key", params, socket) do
    selected = Map.get(params, "contacts", [])
    result = Contacts.send_key(socket.assigns.author, selected, url(socket))

    socket
    |> update(:key_sent_to, &Enum.uniq(&1 ++ result.sent))
    |> assign(selected_contacts: [], error_message: result.error_message)
    |> append_logs(result.log_entries)
    |> noreply()
  end

  def handle_event("clear_error", _params, socket) do
    socket |> assign(error_message: nil) |> noreply()
  end

  # --- Private ---

  # The shape lags Postgres, so a tip that still matches proves nothing about a
  # write in flight — the server re-checks parent_sign_hash either way. This only
  # spares the author a round trip when the divergence is already visible.
  defp concurrent_edit(review, base_url) do
    case ReviewLoader.current_sign_hash(review.review_hash, base_url) do
      {:ok, hash} when hash == review.sign_hash -> nil
      {:ok, _other} -> "Review was modified elsewhere — reselect the origin before editing"
      {:error, _reason} -> "Could not read the current review version — try again"
    end
  end

  defp apply_edit(socket, author, review, rating, text) do
    case ApiClient.edit_review(author, review, rating, text, url(socket)) do
      {:ok, %{review: updated, log_entries: logs}} ->
        socket
        |> assign(review: updated, editing: false)
        |> update_review(updated)
        |> append_logs(logs)

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(error_message: "Edit rejected: #{reason} — see the request log")
        |> append_logs(logs)
    end
  end

  defp moderation_assigns(%{
         assigns: %{author: a, right_candidates: c, shared_secrets: s, review: r}
       }),
       do: {a, c, s, r}

  defp url(socket), do: public_url(socket)

  defp noreply(socket), do: {:noreply, socket}
end
