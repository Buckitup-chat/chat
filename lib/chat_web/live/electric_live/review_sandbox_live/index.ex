defmodule ChatWeb.ElectricLive.ReviewSandboxLive.Index do
  @moduledoc "Interactive sandbox for testing review author operations via Electric API."

  use ChatWeb, :live_view

  import ChatWeb.ElectricLive.ReviewSandboxLive.Render

  alias Chat.Data.Schemas.Origin
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ApiClient
  alias ChatWeb.ElectricLive.ReviewSandboxLive.Contacts
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ListPassword
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ReviewList
  alias ChatWeb.ElectricLive.ReviewSandboxLive.Verification
  alias ChatWeb.ElectricLive.ShapeReader

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(
      author: nil,
      origin_hash: nil,
      moderation_mode: nil,
      review: nil,
      rights_submitted: false,
      right_candidates: nil,
      shared_secrets: %{},
      verification: nil,
      rights_signed: false,
      request_log: [],
      error_message: nil,
      origins: [],
      selected_rating: 0,
      proof_hashes: %{},
      observed_proofs: nil,
      review_list: %{entry: nil},
      peers: [],
      selected_contacts: [],
      key_sent_to: []
    )
    |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)
    |> tap(fn s -> if connected?(s), do: fetch_origins_async(public_url(s)) end)
    |> ok()
  end

  @impl true
  def render(assigns), do: render_page(assigns)

  # --- Info ---

  @impl true
  def handle_info({:origins_loaded, origins}, socket) do
    socket |> assign(origins: origins) |> noreply()
  end

  # --- Events ---

  @impl true
  def handle_event("validate_key_file", _params, socket), do: {:noreply, socket}

  def handle_event("import_keys", _params, socket) do
    [result] =
      consume_uploaded_entries(socket, :key_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case Crypto.parse_and_validate_identity(result) do
      {:ok, user_data} ->
        {:noreply, load_author(socket, user_data)}

      {:error, reason} ->
        socket |> assign(error_message: "Import failed: #{reason}") |> noreply()
    end
  end

  def handle_event("form_changed", %{"origin_hash" => origin_hash}, socket) do
    mode = find_moderation_mode(socket.assigns.origins, origin_hash)
    socket |> assign(origin_hash: origin_hash, moderation_mode: mode) |> noreply()
  end

  def handle_event("set_rating", %{"rating" => rating}, socket) do
    socket |> assign(selected_rating: String.to_integer(rating)) |> noreply()
  end

  def handle_event(
        "submit_review",
        %{"origin_hash" => origin_hash, "rating" => raw_rating} = params,
        socket
      ) do
    text = Map.get(params, "content", "")
    rating = String.to_integer(raw_rating)

    case ApiClient.submit_review(
           socket.assigns.author,
           origin_hash,
           rating,
           text,
           public_url(socket)
         ) do
      {:ok, %{review: review, log_entries: logs}} ->
        socket
        |> assign(review: review, origin_hash: origin_hash)
        |> append_logs(logs)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs) |> noreply()
    end
  end

  def handle_event("submit_rights", _params, socket) do
    %{author: author, review: review} = socket.assigns

    case ApiClient.submit_password_candidates(author, review, public_url(socket)) do
      {:ok, %{candidates: candidates, shared_secrets: shared_secrets} = result} ->
        socket
        |> assign(
          rights_submitted: true,
          right_candidates: candidates,
          shared_secrets: shared_secrets
        )
        |> capture_proof_hashes(result)
        |> append_logs(result.log_entries)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs) |> noreply()
    end
  end

  def handle_event("verify_wrapping", _params, socket) do
    %{
      author: author,
      right_candidates: candidates,
      shared_secrets: shared_secrets,
      review: review
    } = socket.assigns

    verification = Verification.verify_candidates(candidates, shared_secrets, review, author)
    socket |> assign(verification: verification) |> noreply()
  end

  def handle_event("sign_rights", _params, socket) do
    %{
      author: author,
      right_candidates: candidates,
      shared_secrets: shared_secrets,
      review: review
    } =
      socket.assigns

    case ApiClient.sign_right_candidates(
           author,
           candidates,
           shared_secrets,
           review,
           public_url(socket)
         ) do
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

  def handle_event("load_review_list_proofs", _params, socket) do
    observed = ReviewList.load_proofs(socket.assigns.review, public_url(socket))
    socket |> assign(observed_proofs: observed) |> noreply()
  end

  def handle_event("submit_review_list", _params, socket) do
    %{author: author, review: review, moderation_mode: mode, proof_hashes: local} = socket.assigns
    status = ReviewList.proof_status(mode, socket.assigns.observed_proofs, local)
    fields = ReviewList.proof_fields(mode, local, status)

    case ReviewList.submit_entry(author, review, local, fields, public_url(socket)) do
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

    case ReviewList.fill_password_proof(
           author,
           entry,
           local[:review_password_sign_hash],
           public_url(socket)
         ) do
      {:ok, %{entry: filled, log_entries: logs}} ->
        socket
        |> assign(review_list: %{entry: filled})
        |> append_logs(logs)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs) |> noreply()
    end
  end

  def handle_event("select_contacts", params, socket) do
    socket |> assign(selected_contacts: Map.get(params, "contacts", [])) |> noreply()
  end

  def handle_event("send_list_key", params, socket) do
    selected = Map.get(params, "contacts", [])
    result = Contacts.send_key(socket.assigns.author, selected, public_url(socket))

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

  # The server copies these hashes verbatim when it promotes, so they are what
  # review_list must reference. Pre mode deletes the candidates once the rights
  # are signed and ML-DSA-87 signing is randomized, so they cannot be recomputed.
  defp capture_proof_hashes(socket, result) do
    captured =
      result
      |> Map.take([:review_password_sign_hash, :post_right_sign_hash, :revoke_right_sign_hash])

    update(socket, :proof_hashes, &Map.merge(&1, captured))
  end

  defp load_peers(socket) do
    case Contacts.list_peers(socket.assigns.author, public_url(socket)) do
      {:ok, %{peers: peers, log_entries: logs}} ->
        socket |> assign(peers: peers) |> append_logs(logs)

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs)
    end
  end

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))

  # The review_list_password lives in user_storage, so re-importing the same identity
  # (or opening a second tab) reuses the key its contacts already hold.
  defp load_author(socket, user_data) do
    case ListPassword.load_or_create(user_data, public_url(socket)) do
      {:ok, password, logs} ->
        socket
        |> assign(
          author: Map.put(user_data, :review_list_password, password),
          error_message: nil
        )
        |> append_logs(logs)

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(error_message: "Review list password unavailable: #{reason}")
        |> append_logs(logs)
    end
  end

  defp find_moderation_mode(origins, origin_hash) do
    case Enum.find(origins, &(&1.origin_hash == origin_hash)) do
      %{moderation_mode: mode} -> mode
      _ -> nil
    end
  end

  defp fetch_origins_async(base_url) do
    pid = self()

    Task.start_link(fn ->
      origins =
        base_url
        |> ShapeReader.rows("origins", Origin)
        |> Enum.reject(& &1.deleted_flag)
        |> Enum.sort_by(& &1.name)

      send(pid, {:origins_loaded, origins})
    end)
  end
end
