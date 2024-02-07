defmodule ChatWeb.MainLive.Page.ImageGalleryTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  describe "image gallery" do
    setup [:first_person, :second_person]

    test "watch gallery images after transition from invite to room", %{
      first_person: first_person,
      second_person: second_person
    } do
      persons = [first_person, second_person]

      %{}
      |> set_participants(persons)
      |> init_views(persons)
      |> create_room_and_upload_images()
      |> send_room_invitation()
      |> open_dialog_and_upload_image()
      |> accept_room_invitation()
      |> open_room_image_gallery()
      |> check_room_gallery_open_image()
      |> check_room_gallery_images_switch()
    end

    defp check_room_gallery_images_switch(
           %{
             views: [_, view],
             room_messages: [_first, %{id: second_id} | _] = _messages,
             opened: id
           } =
             context
         ) do
      assert view |> has_element?("div #imageGallery .button-container #next")
      assert view |> has_element?("div #imageGallery .button-container #prev")
      assert view |> has_element?("div #topPanel .text-white")

      view
      |> element("#imageGallery #next")
      |> render_click()

      assert view |> has_element?("div #topPanel .text-white", "#{second_id}")

      view
      |> element("#imageGallery #prev")
      |> render_click()

      assert view |> has_element?("div #topPanel .text-white", "#{id}")

      context
    end

    defp check_room_gallery_open_image(%{views: [_, view] = _views} = context) do
      refute view |> has_element?("span", "The message is lost")
      assert view |> has_element?("#galleryImage")

      context
    end

    defp open_room_image_gallery(%{views: [_, view_2] = _views, room_images: _images} = context) do
      with %{socket: %{assigns: %{messages: messages}}, view: view} <-
             reload_view(%{view: view_2}),
           %{id: message_id} <- Enum.find(messages, &(&1.type == :image)) do
        view
        |> element("#chat-image-#{message_id}")
        |> render_click()

        context |> Map.put(:room_messages, messages) |> Map.put(:opened, message_id)
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

    defp create_room_and_upload_images(context),
      do: context |> create_room() |> upload_images("room", 3)

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

    defp upload_images(context, _source, 0), do: context

    defp upload_images(context, source, count),
      do: context |> upload_image(source) |> upload_images(source, count - 1)

    defp upload_image(%{views: [view_1 | _] = _views} = context, source) do
      with %{entry: entry, file: file, filename: filename} <- start_upload(%{view: view_1}),
           entry <- %{entry | done?: true, progress: 100},
           render_upload(file, filename, 100) do
        Map.update(context, atom_image_key(source), [entry], fn prev_entries ->
          [entry | prev_entries]
        end)
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

    defp atom_image_key(source), do: "#{source}_images" |> String.to_atom()
  end
end
