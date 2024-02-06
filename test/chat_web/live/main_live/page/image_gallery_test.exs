defmodule ChatWeb.MainLive.Page.ImageGalleryTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  describe "image gallery" do
    setup [:first_person, :second_person]

    test "open gallery after transition from intive to room", %{
      first_person: first_person,
      second_person: second_person
    } do
      persons = [first_person, second_person]

      %{}
      |> set_participants(persons)
      |> init_views(persons)
      |> create_room_and_upload_image()
      |> send_room_invitation()
      |> open_dialog_and_upload_image()
      |> accept_room_invitation()
      |> open_room_image_gallery()
    end

    defp open_room_image_gallery(%{views: [_, view_2] = _views, room_image: _uuid} = context) do
      with %{socket: %{assigns: %{messages: messages}} = _socket, view: view} <-
             reload_view(%{view: view_2}),
           %{id: message_id} = _message <-
             Enum.find(messages, fn %{type: type} = _message -> type == :image end) do
        view
        |> element("#chat-image-#{message_id}")
        |> render_click()

        assert view |> has_element?("#galleryImage")

        # TODO: check gallery image state

        context
      end
    end

    defp accept_room_invitation(
           %{views: [_, view] = _views, participants: %{sender: sender}} = context
         ) do
      %{view: view}
      |> open_dialog(sender)
      |> update_context_view(context)
      |> select_room_invitation()
      |> render_click()

      assert view |> has_element?("#roomHeader")

      context
    end

    defp create_room_and_upload_image(context),
      do: context |> create_room() |> upload_image("room")

    defp open_dialog_and_upload_image(
           %{views: [view | _] = _views, participants: %{recipient: recipient}} = context
         ) do
      view |> element(".t-chats") |> render_click()

      %{view: view}
      |> open_dialog(recipient)
      |> update_context_view(context)
      |> upload_image("dialog")
    end

    defp send_room_invitation(%{views: [view | _] = _views} = context) do
      view
      |> element("#roomInviteButton")
      |> render_click()

      assert view |> has_element?("#room-invite-list")

      view
      |> element("a", "Send invite")
      |> render_click()

      view
      |> element("#modal-content .phx-modal-close")
      |> render_click()

      context
    end

    defp upload_image(%{views: [view_1 | _] = _views} = context, source) do
      with %{entry: entry, file: file, filename: filename} <- start_upload(%{view: view_1}),
           entry <- %{entry | done?: true, progress: 100},
           render_upload(file, filename, 100) do
        Map.put(context, "#{source}_image" |> String.to_atom(), entry)
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

    defp update_context_view(%{view: view}, %{views: views} = context) do
      views
      |> List.replace_at(which_view_update?(context), view)
      |> put_context_value({:views, context})
    end

    defp put_context_value(value, {key, context}), do: Map.put(context, key, value)

    defp first_person(%{conn: _} = conn), do: [first_person: prepare_view(conn, "Bonnie")]
    defp second_person(%{conn: _} = conn), do: [second_person: prepare_view(conn, "Clyde")]

    defp which_view_update?(context), do: if(Map.has_key?(context, :dialog_image), do: 1, else: 0)

    defp set_participants(context, persons) do
      persons
      |> extract_sockets()
      |> then(fn [%{assigns: %{me: sender}}, %{assigns: %{me: recipient}}] ->
        %{sender: sender, recipient: recipient}
      end)
      |> put_context_value({:participants, context})
    end

    defp extract_sockets(persons),
      do: Enum.map(persons, fn %{socket: socket} = _person -> socket end)

    defp extract_views(persons) when is_list(persons),
      do: Enum.map(persons, fn %{view: view} -> view end)

    defp select_room_invitation(%{views: [_, view]} = _context),
      do: element(view, "button", "Accept and Open")
  end
end
