defmodule ChatWeb.ElectricLive.ReviewSandboxLive.Index do
  @moduledoc "Interactive sandbox for testing review author operations via Electric API."

  use ChatWeb, :live_view

  import ChatWeb.ElectricLive.ReviewSandboxLive.Render

  alias Chat.Data.Schemas.Origin
  alias ChatWeb.ElectricLive.ReviewSandboxLive.Router
  alias ChatWeb.ElectricLive.ShapeReader

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(
      author: nil,
      origin_hash: nil,
      moderation_mode: nil,
      reviews: [],
      review: nil,
      editing: false,
      edit_text: "",
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

  @impl true
  def handle_info({:origins_loaded, origins}, socket) do
    socket |> assign(origins: origins) |> noreply()
  end

  @impl true
  def handle_event(event, params, socket), do: Router.handle_event(event, params, socket)

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
