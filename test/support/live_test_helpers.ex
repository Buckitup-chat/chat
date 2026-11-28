defmodule ChatWeb.LiveTestHelpers do
  @moduledoc """
  LiveView test helpers.
  """

  use ChatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ChatWeb.LiveTestHelpers.{Vue, VueDebug}
  alias Phoenix.LiveView.{Socket, UploadEntry, Utils}

  @type socket :: %Socket{}
  @type view :: %Phoenix.LiveViewTest.View{}

  defdelegate has_vue_content?(view, component_name, content_or_validator), to: Vue
  defdelegate has_vue_content?(view, component_name, content_or_validator, opts), to: Vue
  defdelegate find_vue_component(html, component_name), to: Vue
  defdelegate debug_vue_components(view), to: VueDebug
  defdelegate debug_vue_components(view, component_filter), to: VueDebug
  defdelegate extract_slot_content(view, component_name), to: VueDebug
  defdelegate extract_slot_content(view, component_name, slot_name), to: VueDebug

  @spec prepare_view(%{conn: Plug.Conn.t()}) :: %{socket: Socket.t(), view: view()}
  def prepare_view(%{conn: conn}, name \\ "User") do
    {:ok, view, _html} = live(conn, "/trusted")

    render_hook(view, "restoreAuth")

    view
    |> form("#login-form", login: %{name: name})
    |> render_submit()

    set_local_time(%{view: view})

    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @spec reload_view(%{view: view()}) :: %{socket: Socket.t(), view: view()}
  def reload_view(%{view: view}) do
    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @spec set_local_time(%{view: view()}) :: %{socket: Socket.t(), view: view()}
  def set_local_time(%{view: view}) do
    render_hook(view, "local-time", %{
      "locale" => "en-US",
      "timestamp" => 1_675_181_845,
      "timezone" => "Europe/Sarajevo",
      "timezone_offset" => 1
    })

    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @doc """
  Polls for a condition to become true within a specified timeout.
  Useful for flaky tests where LiveView and Vue component rendering might take time.

  ## Examples

      # Wait until a message appears in the HTML
      wait_until(fn ->
        render(view) =~ "Expected message text"
      end)
      
      # Wait with a custom timeout and interval
      wait_until(
        fn -> render(view) =~ "Expected text" end,
        "Text should appear", 
        timeout: 2000, 
        interval: 200
      )
  """
  @spec wait_until((-> boolean()), String.t(), keyword()) :: :ok | {:error, String.t()}
  def wait_until(condition_fn, message \\ "Condition to be true", opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 100)
    start_time = System.monotonic_time(:millisecond)

    wait_loop(condition_fn, message, timeout, interval, start_time)
  end

  defp wait_loop(condition_fn, message, timeout, interval, start_time) do
    cond do
      condition_fn.() ->
        :ok

      System.monotonic_time(:millisecond) - start_time > timeout ->
        {:error, "Timed out waiting for: #{message}"}

      true ->
        Process.sleep(interval)
        wait_loop(condition_fn, message, timeout, interval, start_time)
    end
  end

  @spec login_by_key(%{conn: Plug.Conn.t()}, String.t()) :: %{socket: Socket.t(), view: view()}
  def login_by_key(%{conn: conn}, path \\ "/trusted") do
    {:ok, view, _html} = live(conn, path)

    render_hook(view, "restoreAuth")
    set_local_time(%{view: view})

    view
    |> element("#importKeyButton")
    |> render_click()

    view
    |> file_input("#my-keys-file-form", :my_keys_file, [
      %{
        last_modified: 1_594_171_879_000,
        name: "TestUser.data",
        content: File.read!("test/support/fixtures/import_keys/TestUser.data"),
        size: 113,
        type: "text/plain"
      }
    ])
    |> render_upload("TestUser.data")

    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @spec open_dialog(%{view: view()}) :: %{socket: Socket.t(), view: view()}
  def open_dialog(%{view: view}, user \\ nil) do
    user_item =
      case user do
        nil ->
          "#chatRoomBar ul li.hidden"

        _ ->
          user = user |> Chat.Card.from_identity()
          "#chatRoomBar #user-#{user.hash}"
      end

    view
    |> element(user_item, if(user, do: "", else: "My notes"))
    |> render_click()

    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @spec create_and_open_room(%{view: view()}, String.t()) :: %{socket: Socket.t(), view: view()}
  def create_and_open_room(%{view: view}, type \\ "public") do
    view
    |> element("button:first-child", "Rooms")
    |> render_click()

    name = Utils.random_id()

    view
    |> form("#room-create-form", room_input: %{name: name, type: type})
    |> render_submit()

    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @spec start_upload(%{view: view()}) :: %{
          entry: UploadEntry.t() | nil,
          file: map(),
          filename: String.t(),
          socket: socket()
        }
  def start_upload(%{view: view}) do
    filename = "#{Utils.random_id()}.jpeg"

    file =
      file_input(view, "#uploader-file-form", :file, [
        %{
          last_modified: 1_594_171_879_000,
          name: filename,
          content:
            Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+P+/HgAFhAJ/wlseKgAAAABJRU5ErkJggg=="
            ),
          size: 70,
          type: "image/jpeg"
        }
      ])

    render_upload(file, filename, 0)

    state = :sys.get_state(view.pid)
    socket = state.socket
    last_entry = List.last(socket.assigns.uploads.file.entries)

    %{entry: last_entry, file: file, filename: filename, socket: socket}
  end
end
