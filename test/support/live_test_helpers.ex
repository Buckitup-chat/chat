defmodule ChatWeb.LiveTestHelpers do
  @moduledoc """
  LiveView test helpers.
  """

  use ChatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.{Socket, UploadEntry, Utils}

  @type socket :: %Socket{}
  @type view :: %Phoenix.LiveViewTest.View{}

  @spec prepare_view(%{conn: Plug.Conn.t()}) :: %{socket: Socket.t(), view: view()}
  def prepare_view(%{conn: conn}, name \\ "User") do
    {:ok, view, _html} = live(conn, "/")

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

  @spec login_by_key(%{conn: Plug.Conn.t()}, String.t()) :: %{socket: Socket.t(), view: view()}
  def login_by_key(%{conn: conn}, path \\ "/") do
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
