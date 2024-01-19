defmodule ChatWeb.MainLive.Page.ImageGalleryTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias ChatWeb.MainLive.Page.ImageGallery

  describe "image gallery" do
    setup [:first_person, :second_person]

    test "open gallery after transition from intive to room", %{
      first_person: first_person,
      second_person: second_person,
      conn: conn
    } do
      IO.inspect(conn)

      %{view: fist_person_view} = first_person
      %{view: second_person_view} = second_person

      {fist_person_view, second_person_view} |> IO.inspect(label: "views")
    end

    defp first_person(%{conn: _} = conn), do: [first_person: login_by_key(conn)]
    defp second_person(%{conn: _} = conn), do: [second_person: login_by_key(conn)]
  end
end
