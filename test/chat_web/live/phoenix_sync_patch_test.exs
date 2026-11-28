defmodule ChatWeb.PhoenixSyncPatchTest do
  use ExUnit.Case, async: true

  import ChatWeb.PhoenixSyncPatch

  alias Electric.Client
  alias Electric.Client.Offset
  alias Electric.Client.ShapeDefinition
  alias Phoenix.LiveView.Socket

  @schema %{id: %{type: "text"}, name: %{type: "text"}}
  # stream events hop through the stream task and the mock client; 100ms is too tight under load
  @stream_timeout 1_000

  defmodule RefusingFetch do
    @moduledoc false
    @behaviour Electric.Client.Fetch

    @impl true
    def validate_opts(opts), do: {:ok, opts}

    @impl true
    def fetch(_request, _opts), do: {:error, :econnrefused}
  end

  describe "sync_stream_fixed/4" do
    # Electric.Client.Fetch.Pool coalesces identical requests across clients, so
    # each test syncs its own table to keep async tests off each other's mocks
    setup do
      %{table: "users_#{System.unique_integer([:positive])}"}
    end

    test "disconnected socket gets an empty stream and no client calls", %{table: table} do
      socket = sync_stream_fixed(bare_socket(), :users, shape(table), client: :never_used)

      assert %{users: _} = socket.assigns.streams
      refute_received {:sync, _}
    end

    test "initial load streams inserts, replays updates and deletes, then goes live",
         %{table: table} do
      {:ok, client} = Client.Mock.new()

      respond(client, table, 0, [
        change("1", "Alice"),
        change("2", "Bob", :update),
        change("3", "Carol", :delete),
        Client.Mock.up_to_date()
      ])

      socket = sync_stream_fixed(connected_socket(), :users, shape(table), client: client)

      assert [{"users-1", %{"id" => "1", "name" => "Alice"}}] = streamed(socket, :users)

      assert_receive {:sync, {:"$electric_event", :users, :insert, %{"id" => "2"}, []}},
                     @stream_timeout

      assert_receive {:sync, {:"$electric_event", :users, :delete, %{"id" => "3"}, []}},
                     @stream_timeout

      assert_receive {:sync, {:users, :loaded}}, @stream_timeout

      respond(client, table, 1, [change("4", "Dave"), Client.Mock.up_to_date()])

      assert_receive {:sync, {:"$electric_event", :users, :insert, %{"id" => "4"}, []}},
                     @stream_timeout

      assert_receive {:sync, {:users, :live}}, @stream_timeout
    end

    test "inside a component events are wrapped with the component id", %{table: table} do
      {:ok, client} = Client.Mock.new()
      cid = %Phoenix.LiveComponent.CID{cid: 7}

      respond(client, table, 0, [change("1", "Alice", :update), Client.Mock.up_to_date()])

      connected_socket()
      |> put_in([Access.key(:assigns), :myself], cid)
      |> sync_stream_fixed(:users, shape(table), client: client)

      assert_receive {:sync,
                      {:"$electric_component_event", ^cid,
                       {:"$electric_event", :users, :insert, %{"id" => "1"}, []}}},
                     @stream_timeout

      assert_receive {:sync, {:"$electric_component_event", ^cid, {:users, :loaded}}},
                     @stream_timeout
    end

    test "initial load error is reported instead of going live", %{table: table} do
      {:ok, client} = Client.Mock.new()

      Client.Mock.async_response(client,
        status: 400,
        body: %{"message" => "bad where clause"}
      )

      socket = sync_stream_fixed(connected_socket(), :users, shape(table), client: client)

      assert [] = streamed(socket, :users)
      assert_receive {:sync, {:users, {:error, message}}}, @stream_timeout
      assert is_binary(message)
      refute_received {:sync, {:users, :loaded}}
    end

    test "live stream error is reported", %{table: table} do
      {:ok, client} = Client.Mock.new()

      respond(client, table, 0, [Client.Mock.up_to_date()])
      sync_stream_fixed(connected_socket(), :users, shape(table), client: client)
      assert_receive {:sync, {:users, :loaded}}, @stream_timeout

      Client.Mock.async_response(client, status: 400, body: [%{"message" => "gone"}])

      assert_receive {:sync, {:users, {:error, message}}}, @stream_timeout
      assert is_binary(message)
    end

    test "transport failure without a response body is reported", %{table: table} do
      {:ok, client} =
        Client.new(base_url: "http://unreachable.electric", fetch: {RefusingFetch, []})

      socket = sync_stream_fixed(connected_socket(), :users, shape(table), client: client)

      assert [] = streamed(socket, :users)

      assert_receive {:sync, {:users, {:error, "Unable to retrieve data stream"}}},
                     @stream_timeout
    end
  end

  describe "sync_stream_update/3" do
    test "delegates inserts and deletes to Phoenix.Sync" do
      socket = Phoenix.LiveView.stream(bare_socket(), :users, [])
      item = %{"id" => "1"}

      inserted =
        sync_stream_update(socket, {:"$electric_event", :users, :insert, item, []}, at: 0)

      assert [{"users-1", ^item}] = streamed(inserted, :users)

      deleted = sync_stream_update(inserted, {:"$electric_event", :users, :delete, item, []})
      assert %{deletes: [_]} = deleted.assigns.streams.users
    end

    test "status events leave the socket unchanged" do
      socket = Phoenix.LiveView.stream(bare_socket(), :users, [])

      assert socket == sync_stream_update(socket, {:users, :loaded})
      assert socket == sync_stream_update(socket, {:users, :live})
    end
  end

  # Helpers

  defp shape(table), do: ShapeDefinition.new!(table)

  defp connected_socket, do: %{bare_socket() | transport_pid: self()}

  defp bare_socket do
    %Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}}
    |> Phoenix.LiveView.stream_configure(:users, dom_id: &"users-#{&1["id"]}")
  end

  defp change(id, name, operation \\ :insert),
    do: Client.Mock.change(value: %{id: id, name: name}, operation: operation)

  defp respond(client, table, offset, body) do
    Client.Mock.async_response(client,
      status: 200,
      schema: @schema,
      last_offset: Offset.new(0, offset),
      shape_handle: "#{table}-shape",
      body: body
    )
  end

  defp streamed(socket, name) do
    socket.assigns.streams
    |> Map.fetch!(name)
    |> Map.fetch!(:inserts)
    |> Enum.map(fn {dom_id, _at, item, _limit} -> {dom_id, item} end)
  end
end
