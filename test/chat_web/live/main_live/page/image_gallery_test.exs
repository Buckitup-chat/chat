defmodule ChatWeb.MainLive.Page.ImageGalleryTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  describe "image gallery" do
    setup [:setup_persons]

    test "watch gallery images after transition from invite to room",
         %{first_person: first_person, second_person: second_person} = context do
      context
      |> init_gallery_workflow([first_person, second_person])
      |> test_image_gallery_flow()
    end

    defp setup_persons(%{conn: _} = conn) do
      {:ok,
       first_person: prepare_view(conn, "Bonnie"), second_person: prepare_view(conn, "Clyde")}
    end

    defp init_gallery_workflow(context, persons) do
      context
      |> set_participants(persons)
      |> init_views(persons)
      |> create_room_and_upload_images()
      |> send_room_invitation()
      |> open_dialog_with_invite()
      |> upload_dialog_images()
      |> open_dialog_image_gallery()
    end

    defp test_image_gallery_flow(context) do
      context
      |> check_gallery_image_switch(:dialog)
      |> close_image_gallery()
      |> accept_room_invitation()
      |> open_room_image_gallery()
      |> check_room_gallery_open_image()
      |> check_gallery_image_switch(:room)
      |> close_image_gallery()
    end

    defp close_image_gallery(%{views: [_, view], opened: id} = context) do
      view |> click_element("#backBtn button", "Back")
      view |> assert_no_element("div #topPanel .text-white", id)

      context
    end

    defp check_gallery_image_switch(%{views: [_, view]} = context, type) do
      {id, second_id} = context |> fetch_image_ids(type)

      context
      |> assert_navigation_buttons(view)
      |> navigate_and_assert_image(view, :next, second_id)
      |> navigate_and_assert_image(view, :prev, id)
    end

    defp assert_navigation_buttons(context, view) do
      Enum.each([:next, :prev], fn type ->
        assert view |> has_element?("div #imageGallery .button-container #{button_id(type)}")
      end)

      context
    end

    defp navigate_and_assert_image(context, view, direction, expected_id) do
      view
      |> click_element("#imageGallery #{button_id(direction)}")

      view
      |> assert_element("div #topPanel .text-white", expected_id)

      context
    end

    defp button_id(:next), do: "#next"
    defp button_id(:prev), do: "#prev"

    defp fetch_image_ids(context, type) do
      messages = context |> Map.fetch!(atom_image_key(type))
      {Enum.at(messages, 0).id, Enum.at(messages, 1).id}
    end

    defp click_element(view, selector, action \\ nil) do
      view |> element(selector, action) |> render_click()
    end

    defp assert_element(view, selector, expected_value) do
      assert view |> has_element?(selector, "#{expected_value}")
    end

    defp assert_no_element(view, selector, unexpected_value) do
      refute view |> has_element?(selector, "#{unexpected_value}")
    end

    defp check_room_gallery_open_image(%{views: [_, view] = _views} = context) do
      refute view |> has_element?("span", "The message is lost")
      assert view |> has_element?("#galleryImage")

      context
    end

    defp open_dialog_image_gallery(
           %{
             views: [_, view] = _views,
             dialog_image_messages: [%{id: message_id}, _] = _messages
           } = context
         ) do
      view
      |> element("#chat-image-#{message_id}")
      |> render_click()

      assert view |> has_element?("#galleryImage")

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
