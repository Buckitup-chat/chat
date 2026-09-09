defmodule ChatWeb.ElectricLive.ReviewSandboxLive.State do
  @moduledoc """
  Socket-state transitions for the Review Author Sandbox.

  Keeps the pipeline assigns (steps 3-5) honest about which review they describe:
  they are cleared when the sandbox moves to a different review, restored when an
  already-published one is loaded back, and left alone by an edit — which changes
  the review's content but none of the rows hanging off it.
  """

  import ChatWeb.LiveHelpers, only: [public_url: 1]
  import Phoenix.Component

  alias ChatWeb.ElectricLive.ReviewSandboxLive.Contacts
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ListPassword
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ReviewList
  alias ChatWeb.ElectricLive.ReviewSandboxLive.ReviewLoader

  @pipeline_assigns [
    rights_submitted: false,
    right_candidates: nil,
    shared_secrets: %{},
    verification: nil,
    rights_signed: false,
    proof_hashes: %{},
    observed_proofs: nil,
    review_list: %{entry: nil},
    peers: [],
    selected_contacts: [],
    key_sent_to: []
  ]

  @doc "Drops the current review and everything the pipeline built on top of it."
  def reset_review(socket) do
    socket |> assign(review: nil, editing: false) |> assign(@pipeline_assigns)
  end

  @doc "Points the sandbox at `origin_hash`, listing the reviews already written there."
  def select_origin(socket, nil) do
    socket |> assign(origin_hash: nil, moderation_mode: nil, reviews: []) |> reset_review()
  end

  def select_origin(socket, origin_hash) do
    socket
    |> assign(origin_hash: origin_hash, moderation_mode: moderation_mode(socket, origin_hash))
    |> reset_review()
    |> load_reviews(origin_hash)
  end

  @doc "Switches to the review `review_hash`, if it is one that can be opened."
  def select_review(socket, review_hash) do
    case Enum.find(socket.assigns.reviews, &(&1.review_hash == review_hash and &1.review)) do
      nil -> socket
      item -> socket |> reset_review() |> open(item)
    end
  end

  @doc "Adds a freshly written review to the origin's list and works on it."
  def add_review(socket, review) do
    item = %{
      review_hash: review.review_hash,
      owner_timestamp: review.owner_timestamp,
      review: review,
      entry: nil,
      error: nil
    }

    socket |> update(:reviews, &[item | &1]) |> assign(review: review)
  end

  @doc "Reflects an edit in the origin's list without re-reading the shapes."
  def update_review(socket, review) do
    update(socket, :reviews, &Enum.map(&1, fn item -> replace(item, review) end))
  end

  defp replace(%{review_hash: hash} = item, %{review_hash: hash} = review),
    do: %{item | review: review, owner_timestamp: review.owner_timestamp}

  defp replace(item, _review), do: item

  @doc "Records the moderation-proof hashes the server minted for this review."
  def capture_proof_hashes(socket, result) do
    hashes =
      Map.take(result, [
        :review_password_sign_hash,
        :post_right_sign_hash,
        :revoke_right_sign_hash
      ])

    update(socket, :proof_hashes, &Map.merge(&1, hashes))
  end

  @doc """
  Takes on a proof the shape now shows but this session never signed.

  Only for a review loaded from the shapes: the server copies a candidate's
  `sign_hash` verbatim on promotion, so what the shape holds is what the author
  signed in some earlier session. Hashes captured in this session always win.
  """
  def adopt_proofs(%{assigns: %{review: %{loaded?: true}}} = socket, observed) do
    update(socket, :proof_hashes, fn local ->
      Map.merge(observed, local, fn _slot, from_shape, from_session ->
        from_session || from_shape
      end)
    end)
  end

  def adopt_proofs(socket, _observed), do: socket

  @doc "Imports an author identity together with their `review_list_password`."
  def load_author(socket, user_data) do
    case ListPassword.load_or_create(user_data, public_url(socket)) do
      {:ok, password, logs} ->
        author = Map.put(user_data, :review_list_password, password)
        socket |> assign(author: author, error_message: nil) |> append_logs(logs)

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(error_message: "Review list password unavailable: #{reason}")
        |> append_logs(logs)
    end
  end

  @doc "Loads the contacts the author can hand their review_list key to."
  def load_peers(socket) do
    case Contacts.list_peers(socket.assigns.author, public_url(socket)) do
      {:ok, %{peers: peers, log_entries: logs}} ->
        socket |> assign(peers: peers) |> append_logs(logs)

      {:error, %{reason: reason, log_entries: logs}} ->
        socket |> assign(error_message: reason) |> append_logs(logs)
    end
  end

  @doc "Prepends `logs` to the request log."
  def append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))

  defp moderation_mode(socket, origin_hash) do
    Enum.find_value(
      socket.assigns.origins,
      &if(&1.origin_hash == origin_hash, do: &1.moderation_mode)
    )
  end

  defp load_reviews(%{assigns: %{author: nil}} = socket, _origin_hash),
    do: assign(socket, reviews: [])

  defp load_reviews(socket, origin_hash) do
    items = ReviewLoader.list_for_origin(socket.assigns.author, origin_hash, public_url(socket))

    case Enum.find(items, & &1.review) do
      nil -> assign(socket, reviews: items)
      newest -> socket |> assign(reviews: items) |> open(newest)
    end
  end

  # A review that came back with a review_list row has necessarily been through
  # steps 3-5 — that row is where its password came from. Re-running them would
  # only mint candidates the server will not promote a second time, so its pipeline
  # is restored as already done, with the proof hashes taken from the shapes.
  defp open(socket, %{review: review, entry: nil}) do
    assign(socket, review: review, selected_rating: review.rating)
  end

  defp open(socket, %{review: review, entry: entry}) do
    proofs = ReviewList.load_proofs(review, public_url(socket))

    socket
    |> assign(
      review: review,
      selected_rating: review.rating,
      rights_submitted: true,
      rights_signed: true,
      observed_proofs: proofs,
      proof_hashes: proofs,
      review_list: %{entry: entry}
    )
    |> load_peers()
  end
end
