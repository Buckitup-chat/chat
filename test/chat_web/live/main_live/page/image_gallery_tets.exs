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

      %{}
      |> init_views(persons)
      |> create_room()
      |> upload_image()
      |> send_room_invite()
      |> add_dialog_gallery()
    end

    defp add_dialog_gallery(%{views: [view | _] = _views} = context) do
      # TODO: upload image to dialog with Clyde

      context
    end

    defp send_room_invite(%{views: [view | _] = _views} = context) do
      view
      |> element("#roomInviteButton")
      |> render_click()

      view
      |> element("a", "Send invite")
      |> render_click()

      context
    end

    defp upload_image(%{views: [view_1 | _] = _views} = context) do
      with %{entry: entry, socket: _socket_1} <- start_upload(%{view: view_1}),
           entry <- %{entry | done?: true, progress: 100},
           :ok <- ChangeTracker.await() do
        Map.put(context, :room_upload_entry, entry)
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
