defmodule ChatWeb.MainLive.Page.ImageGalleryTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias ChatWeb.MainLive.Page.ImageGallery

  alias Chat.Db.ChangeTracker

  describe "image gallery" do
    setup [:first_person, :second_person]

    test "open gallery after transition from intive to room", %{
      first_person: first_person,
      second_person: second_person
    } do
      persons = [first_person, second_person]

      [_socket1, %{assigns: %{me: recipient}} = socket2] = persons |> extract_sockets()

      %{}
      |> init_views(persons)
      |> create_room_with_upload_image()
      |> send_room_invite()
      |> add_dialog_gallery(recipient: recipient)

      # |> accept_room_invitation("Bonnie")
    end

    defp accept_room_invitation(%{views: [_ | view] = _views} = context, name) do
      %{view: view}
      |> open_dialog(name)

      # TODO: write room invitation acceptance

      context
    end

    defp create_room_with_upload_image(context),
      do: context |> create_room() |> upload_image("room")

    defp add_dialog_gallery(%{views: [view | _] = _views} = context, recipient: user) do
      view |> element(".t-chats") |> render_click()

      %{view: view}
      |> open_dialog(user)
      |> update_context_view(context)
      |> upload_image("dialog")
    end

    defp send_room_invite(%{views: [view | _] = _views} = context) do
      view
      |> element("#roomInviteButton")
      |> render_click()

      view
      |> element("a", "Send invite")
      |> render_click()

      view
      |> element("#modal-content")
      |> render_keydown()

      refute view |> has_element?("#modal-content", "Send room invite")

      context
    end

    defp upload_image(%{views: [view_1 | _] = _views} = context, source) do
      with %{entry: entry, socket: _socket_1} <- start_upload(%{view: view_1}),
           entry <- %{entry | done?: true, progress: 100},
           :ok <- ChangeTracker.await() do
        Map.put(context, "#{source}_image", entry)
      else
        _ -> context
      end
    end

    defp create_room(%{views: [view_1 | _] = _views} = context) do
      %{view: view_1}
      |> create_and_open_room()
      |> update_context_view(context)
    end

    defp init_views(context, persons),
      do: persons |> extract_views() |> put_context_value({:views, context})

    defp update_context_view(%{view: view}, %{views: views} = context),
      do: views |> List.replace_at(0, view) |> put_context_value({:views, context})

    defp put_context_value(value, {key, context}), do: Map.put(context, key, value)

    defp first_person(%{conn: _} = conn), do: [first_person: prepare_view(conn, "Bonnie")]
    defp second_person(%{conn: _} = conn), do: [second_person: prepare_view(conn, "Clyde")]

    defp extract_sockets(persons),
      do: Enum.map(persons, fn %{socket: socket} = _person -> socket end)

    defp extract_views(persons) when is_list(persons),
      do: Enum.map(persons, fn %{view: view} -> view end)
  end
end
