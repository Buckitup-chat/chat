defmodule ChatWeb.ElectricLive.StreamIndex do
  @moduledoc """
  Macro and components for Electric stream listing views.

  Generates mount/handle_info boilerplate and provides a shared
  page component with status indicators and loading state.

      defmodule ChatWeb.ElectricLive.ReviewPostRightsLive.Index do
        use ChatWeb.ElectricLive.StreamIndex,
          stream: :records,
          table: "review_post_right",
          schema: Chat.Data.Schemas.ReviewPostRight

        defp dom_id(%ReviewPostRight{review_hash: hash}),
          do: "rpr-\#{Shortcode.short_code(hash)}"

        @impl true
        def render(assigns) do
          ~H\"\"\"
          <StreamIndex.page title="..." subtitle="..." ...>
            <:row :let={record}>
              ...row content...
            </:row>
          </StreamIndex.page>
          \"\"\"
        end
      end
  """

  use Phoenix.Component

  # --- Macro ---

  defmacro __using__(opts) do
    stream = Keyword.fetch!(opts, :stream)
    table = Keyword.fetch!(opts, :table)
    schema = Keyword.fetch!(opts, :schema)

    quote do
      use ChatWeb, :live_view
      import ChatWeb.PhoenixSyncPatch

      alias unquote(schema)
      alias Chat.Proto.Shortcode
      alias ChatWeb.ElectricLive.StreamIndex

      @impl true
      def mount(_params, _session, socket) do
        case connected?(socket) do
          true ->
            endpoint_url = ChatWeb.Endpoint.url() <> "/electric/v1/shapes"
            client = Electric.Client.new!(endpoint: endpoint_url)

            shape =
              Electric.Client.ShapeDefinition.new!(unquote(table),
                parser: {Electric.Client.EctoAdapter, unquote(schema)}
              )

            {:ok,
             socket
             |> Phoenix.LiveView.stream_configure(unquote(stream), dom_id: &dom_id/1)
             |> sync_stream_fixed(unquote(stream), shape, client: client)
             |> assign(loading: false, error: nil, connected: true, live: false)}

          false ->
            {:ok, assign(socket, loading: true, error: nil, connected: false, live: false)}
        end
      end

      @impl true
      def handle_info({:sync, event}, socket) do
        case event do
          {unquote(stream), :loaded} ->
            socket |> assign(loading: false, error: nil) |> noreply()

          {unquote(stream), :live} ->
            socket |> assign(live: true, error: nil) |> noreply()

          {unquote(stream), {:error, reason}} ->
            socket |> assign(loading: false, live: false, error: reason) |> noreply()

          _ ->
            socket |> sync_stream_update(event) |> noreply()
        end
      end
    end
  end

  # --- Components ---

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :stream_header, :string, required: true
  attr :loading_text, :string, required: true
  attr :loading, :boolean, required: true
  attr :connected, :boolean, required: true
  attr :live, :boolean, required: true
  slot :row, required: true

  def page(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="mb-8">
          <a href="/electric" class="text-sm text-blue-600 hover:text-blue-800 mb-2 inline-block">
            &larr; Electric Index
          </a>
          <div class="flex items-center justify-between">
            <div>
              <h1 class="text-3xl font-bold text-gray-900">{@title}</h1>
              <p class="mt-2 text-sm text-gray-600">{@subtitle}</p>
            </div>
            <div class="flex items-center space-x-4">
              <div class="flex items-center space-x-2">
                <span class={"inline-block w-2 h-2 rounded-full #{if @connected, do: "bg-green-500", else: "bg-red-500"}"}>
                </span>
                <span class="text-sm font-medium text-gray-700">
                  {if @connected, do: "Connected", else: "Disconnected"}
                </span>
              </div>
              <span
                :if={@live}
                class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
              >
                Live
              </span>
            </div>
          </div>
        </div>

        <%= if @loading do %>
          <div class="flex flex-col justify-center items-center py-12">
            <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
            <p class="mt-4 text-sm text-gray-600">{@loading_text}</p>
          </div>
        <% else %>
          <div class="bg-white shadow overflow-hidden sm:rounded-lg">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
              <h3 class="text-lg leading-6 font-medium text-gray-900">{@stream_header}</h3>
            </div>
            {render_slot(@row)}
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
