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
      |> open_dialog_with_invite()
      |> upload_dialog_images()
      |> open_dialog_image_gallery()
      |> check_gallery_image_switch(:dialog)
      |> close_image_gallery()
      |> accept_room_invitation()
      |> open_room_image_gallery()
      |> check_room_gallery_open_image()
      |> check_gallery_image_switch(:room)
      |> close_image_gallery()
    end

    defp close_image_gallery(%{views: [_, view] = _views, opened: id} = context) do
      view |> element("#backBtn button", "Back") |> render_click()
      refute view |> has_element?("div #topPanel .text-white", "#{id}")
      context
    end

    defp check_gallery_image_switch(%{views: [_, view]} = context, type) do
      messages = context[atom_image_key(type)]
      {id, second_id} = {Enum.at(messages, 0).id, Enum.at(messages, 1).id}

      context
      |> assert_move_btn(view, :next)
      |> assert_move_btn(view, :prev)
      |> render_click_move(view, :next)
      |> assert_image_element_id(view, second_id)
      |> render_click_move(view, :prev)
      |> assert_image_element_id(view, id)
    end

    defp assert_image_element_id(context, view, value) do
      assert view |> has_element?("div #topPanel .text-white", "#{value}")
      context
    end

    defp render_click_move(context, view, type) do
      view
      |> element(
        "#imageGallery #{case type do
          :next -> "#next"
          :prev -> "#prev"
        end}"
      )
      |> render_click()

      context
    end

    defp assert_move_btn(context, view, type) do
      assert view
             |> has_element?(
               "div #imageGallery .button-container #{case type do
                 :next -> "#next"
                 :prev -> "#prev"
               end}"
             )

      context
    end

    defp check_room_gallery_open_image(%{views: [_, view] = _views} = context) do
      refute view |> has_element?("span", "The message is lost")
      assert view |> has_element?("#galleryImage")

      context
    end

    defp open_dialog_image_gallery(
           %{
             views: [_view_1, view_2] = _views,
             dialog_image_messages: [%{id: message_id}, _] = _messages
           } = context
         ) do
      view_2
      |> element("#chat-image-#{message_id}")
      |> render_click()

      assert view_2 |> has_element?("#galleryImage")

      context |> Map.put(:opened, message_id)
    end
  end

  defp open_room_image_gallery(
         %{views: [_, view] = _views, room_image_messages: [%{id: message_id} | _] = messages} =
           context
       ) do
    view
    |> element("#chat-image-#{message_id}")
    |> render_click()

    context |> Map.put(:room_messages, messages) |> Map.put(:opened, message_id)
  end

  defp open_dialog_with_invite(
         %{views: [_, view] = _views, participants: %{sender: sender}} = context
       ) do
    %{view: view}
    |> open_dialog(sender)
    |> update_context_view(context, :recipient)
  end

  defp accept_room_invitation(%{views: [_, view] = _views} = context) do
    context
    |> select_room_invitation()
    |> render_click()

    assert view |> has_element?("#roomHeader")

    context
  end

  defp create_room_and_upload_images(context),
    do: context |> create_room() |> upload_images("room", 3)

  defp send_room_invitation(
         %{views: [view_1, _], participants: %{recipient: recipient}} = context
       ) do
    recipient_hash = recipient |> Chat.Card.from_identity() |> Map.get(:hash)

    view_1
    |> element("#roomInviteButton")
    |> render_click()

    assert view_1 |> has_element?("#room-invite-list")

    view_1
    |> element("div #user-#{recipient_hash} a", "Send invite")
    |> render_click()

    view_1
    |> element("#modal-content .phx-modal-close")
    |> render_click()

    context
  end

  defp upload_dialog_images(%{views: _views} = context),
    do: context |> upload_images("dialog", 2)

  defp upload_images(context, _source, 0), do: context

  defp upload_images(context, source, count),
    do: context |> upload_image(source) |> upload_images(source, count - 1)

  defp upload_image(%{views: _views} = context, source) do
    with view <- source_view(context, source),
         %{entry: entry, file: file, filename: filename} <-
           start_upload(%{view: view}),
         _entry <- %{entry | done?: true, progress: 100} do
      render_upload(file, filename, 100)
      %{socket: %{assigns: %{messages: messages}}, view: _view} = reload_view(%{view: view})

      case Map.has_key?(context, atom_image_key(source)) do
        true -> Map.update!(context, atom_image_key(source), &(&1 ++ messages))
        false -> Map.put_new(context, atom_image_key(source), messages)
      end
    else
      _ -> context
    end
  end

  defp source_view(%{views: [view_1, view_2]}, source),
    do: if(source == "room", do: view_1, else: view_2)

  defp create_room(%{views: [view_1, _] = _views} = context) do
    %{view: view_1}
    |> create_and_open_room()
    |> update_context_view(context)
  end

  defp init_views(context, persons),
    do: persons |> extract_views() |> put_context_value({:views, context})

  defp update_context_view(%{view: view}, %{views: views} = context, actor \\ :sender) do
    views
    |> List.replace_at(which_view_update?(actor), view)
    |> put_context_value({:views, context})
  end

  defp put_context_value(value, {key, context}), do: Map.put(context, key, value)

  defp first_person(%{conn: _} = conn), do: [first_person: prepare_view(conn, "Bonnie")]
  defp second_person(%{conn: _} = conn), do: [second_person: prepare_view(conn, "Clyde")]

  defp which_view_update?(actor), do: if(actor == :sender, do: 0, else: 1)

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

  defp atom_image_key(source), do: "#{source}_image_messages" |> String.to_atom()
end
