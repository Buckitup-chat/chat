defmodule ChatWeb.ElectricLive.OriginReviewsLive.Index do
  @moduledoc "Public viewer for decrypted reviews on origins."

  use ChatWeb, :live_view

  alias Chat.Data.Schemas.Origin
  alias Chat.Data.Schemas.Review
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Proto.Shortcode
  alias Electric.Client.Message

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        origins: [],
        selected_origin: nil,
        reviews: [],
        loading_origins: true,
        loading_reviews: false
      )

    if connected?(socket), do: fetch_origins_async()

    {:ok, socket}
  end

  @impl true
  def handle_info({:origins_loaded, origins}, socket) do
    {:noreply, assign(socket, origins: origins, loading_origins: false)}
  end

  @impl true
  def handle_info({:reviews_loaded, reviews}, socket) do
    {:noreply, assign(socket, reviews: reviews, loading_reviews: false)}
  end

  @impl true
  def handle_event("select_origin", %{"hash" => origin_hash}, socket) do
    origin = Enum.find(socket.assigns.origins, &(&1.origin_hash == origin_hash))
    fetch_reviews_async(origin_hash)

    {:noreply, assign(socket, selected_origin: origin, reviews: [], loading_reviews: true)}
  end

  def handle_event("back_to_origins", _params, socket) do
    {:noreply, assign(socket, selected_origin: nil, reviews: [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-4xl mx-auto px-4">
        <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
          &larr; Electric Index
        </a>
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Origin Reviews</h1>
        <p class="text-sm text-gray-600 mb-6">Browse public reviews for origins</p>

        <%= if @selected_origin do %>
          <.origin_reviews_view
            origin={@selected_origin}
            reviews={@reviews}
            loading={@loading_reviews}
          />
        <% else %>
          <.origins_directory origins={@origins} loading={@loading_origins} />
        <% end %>
      </div>
    </div>
    """
  end

  # --- Components ---

  attr :origins, :list, required: true
  attr :loading, :boolean, required: true

  defp origins_directory(assigns) do
    ~H"""
    <%= if @loading do %>
      <.spinner text="Loading origins..." />
    <% else %>
      <div class="grid gap-3 sm:grid-cols-2">
        <button
          :for={origin <- @origins}
          phx-click="select_origin"
          phx-value-hash={origin.origin_hash}
          class="text-left bg-white shadow rounded-lg px-4 py-4 hover:shadow-md transition-shadow"
        >
          <p class="font-semibold text-gray-900">{origin.name}</p>
          <p class="mt-1 text-xs text-gray-500">
            <span class="font-mono">{Shortcode.short_code(origin.origin_hash)}</span>
            <span class={"ml-2 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{moderation_badge(origin.moderation_mode)}"}>
              {origin.moderation_mode}
            </span>
          </p>
        </button>
      </div>
      <p :if={@origins == []} class="text-sm text-gray-500 text-center py-8">
        No origins found. Create one in the Origin Sandbox.
      </p>
    <% end %>
    """
  end

  defp moderation_badge(:none), do: "bg-gray-100 text-gray-800"
  defp moderation_badge(:post), do: "bg-yellow-100 text-yellow-800"
  defp moderation_badge(:pre), do: "bg-blue-100 text-blue-800"
  defp moderation_badge(_), do: "bg-gray-100 text-gray-800"

  attr :origin, Origin, required: true
  attr :reviews, :list, required: true
  attr :loading, :boolean, required: true

  defp origin_reviews_view(assigns) do
    ~H"""
    <div>
      <button
        phx-click="back_to_origins"
        class="text-sm text-blue-600 hover:text-blue-800 mb-4 inline-block"
      >
        &larr; Back to origins
      </button>
      <div class="mb-6">
        <h2 class="text-xl font-bold text-gray-900">{@origin.name}</h2>
        <p class="text-xs text-gray-500">
          <span class="font-mono">{Shortcode.short_code(@origin.origin_hash)}</span>
          | Moderation: <span class="font-semibold">{@origin.moderation_mode}</span>
        </p>
      </div>

      <%= if @loading do %>
        <.spinner text="Loading reviews..." />
      <% else %>
        <div class="space-y-4">
          <div :for={review <- @reviews} class="bg-white shadow rounded-lg px-5 py-4">
            <div class="flex items-center justify-between mb-2">
              <.stars rating={review.rating} />
              <span class="text-xs text-gray-400 font-mono">
                {Shortcode.short_code(review.author_hash)}
              </span>
            </div>
            <p :if={review.text != ""} class="text-sm text-gray-700">{review.text}</p>
            <p :if={review.text == ""} class="text-sm text-gray-400 italic">Rating only</p>
          </div>
        </div>
        <p :if={@reviews == []} class="text-sm text-gray-500 text-center py-8">
          No reviews yet for this origin.
        </p>
      <% end %>
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

  attr :text, :string, required: true

  defp spinner(assigns) do
    ~H"""
    <div class="flex flex-col items-center py-12">
      <div class="animate-spin rounded-full h-10 w-10 border-b-2 border-blue-600"></div>
      <p class="mt-4 text-sm text-gray-600">{@text}</p>
    </div>
    """
  end

  # --- Private ---

  defp fetch_origins_async do
    pid = self()
    client = Electric.Client.new!(endpoint: ChatWeb.Endpoint.url() <> "/electric/v1/shapes")

    shape =
      Electric.Client.ShapeDefinition.new!("origins",
        parser: {Electric.Client.EctoAdapter, Origin}
      )

    Task.start_link(fn ->
      origins =
        client
        |> Electric.Client.stream(shape, live: false, replica: :full)
        |> collect_inserts()
        |> Enum.reject(& &1.deleted_flag)
        |> Enum.sort_by(& &1.name)

      send(pid, {:origins_loaded, origins})
    end)
  end

  defp fetch_reviews_async(origin_hash) do
    pid = self()
    client = Electric.Client.new!(endpoint: ChatWeb.Endpoint.url() <> "/electric/v1/shapes")

    review_shape =
      Electric.Client.ShapeDefinition.new!("review",
        where: "origin_hash = '#{origin_hash}'",
        parser: {Electric.Client.EctoAdapter, Review}
      )

    password_shape =
      Electric.Client.ShapeDefinition.new!("review_public_passwords",
        where: "origin_hash = '#{origin_hash}'",
        parser: {Electric.Client.EctoAdapter, ReviewPublicPassword}
      )

    Task.start_link(fn ->
      reviews =
        client
        |> Electric.Client.stream(review_shape, live: false, replica: :full)
        |> collect_inserts()
        |> Enum.reject(& &1.deleted_flag)

      passwords =
        client
        |> Electric.Client.stream(password_shape, live: false, replica: :full)
        |> collect_inserts()
        |> Enum.reject(& &1.deleted_flag)

      decrypted = join_and_decrypt(reviews, passwords)
      send(pid, {:reviews_loaded, decrypted})
    end)
  end

  defp join_and_decrypt(reviews, passwords) do
    password_map = latest_passwords(passwords)

    reviews
    |> Enum.map(fn review ->
      case Map.get(password_map, review.review_hash) do
        %{password_b64: pwd} when is_binary(pwd) -> decrypt_review(review, pwd)
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.owner_timestamp, :desc)
  end

  defp latest_passwords(passwords) do
    passwords
    |> Enum.group_by(& &1.review_hash)
    |> Map.new(fn {hash, entries} -> {hash, Enum.max_by(entries, & &1.owner_timestamp)} end)
  end

  defp decrypt_review(review, password) do
    content = decode_binary(review.content_b64)
    key = decode_binary(password)

    with plaintext when is_binary(plaintext) <- EnigmaPq.aes_gcm_decrypt(content, key),
         [rating, _placeholder, text] <- Jason.decode!(plaintext) do
      %{
        review_hash: review.review_hash,
        rating: rating,
        text: text,
        author_hash: review.author_hash,
        owner_timestamp: review.owner_timestamp
      }
    else
      _ -> nil
    end
  end

  defp decode_binary(value) when is_binary(value) do
    case Base.decode64(value, padding: false) do
      {:ok, decoded} -> decoded
      :error -> value
    end
  end

  defp collect_inserts(stream) do
    Enum.reduce_while(stream, [], fn
      %Message.ChangeMessage{headers: %{operation: :insert}, value: value}, acc ->
        {:cont, [value | acc]}

      %Message.ControlMessage{control: :up_to_date}, acc ->
        {:halt, acc}

      _, acc ->
        {:cont, acc}
    end)
  end
end
