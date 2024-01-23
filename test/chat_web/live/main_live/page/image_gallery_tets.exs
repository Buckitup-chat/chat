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

      [_socket1, socket2] = persons |> extract_sockets()

      %{}
      |> init_views(persons)
      |> create_room()
      |> upload_image("room")
      |> send_room_invite()
      |> add_dialog_gallery(socket2.assigns.me)
      |> accept_room_invitation("Bonnie")
    end

    defp extract_sockets(persons),
      do: Enum.map(persons, fn %{socket: socket} = _person -> socket end)

    defp accept_room_invitation(%{views: [_ | view] = _views} = context, name) do
      %{view: view}
      |> open_dialog(name)
      |> update_context_view(context)
    end

    defp add_dialog_gallery(%{views: [view | _] = _views} = context, user) do
      IO.inspect(context, label: "adding dialog gallery: context")

      %{view: view}
      |> open_dialog(user)
      |> upload_image("dialog")
      |> update_context_view(context)
    end

    defp send_room_invite(%{views: [view | _] = _views} = context) do
      IO.inspect(context, label: "sending room invite: context")

      view
      |> element("#roomInviteButton")
      |> render_click()

      view
      |> element("a", "Send invite")
      |> render_click()

      view
      |> element("#modal .phx-modal-content")
      |> render_keydown()

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

    defp extract_views(persons) when is_list(persons),
      do: Enum.map(persons, fn %{view: view} -> view end)
  end
end
