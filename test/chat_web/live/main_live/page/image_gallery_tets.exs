defmodule ChatWeb.MainLive.Page.ImageGalleryTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias ChatWeb.MainLive.Page.ImageGallery

  describe "image gallery" do
    setup [:create_initial_state]
    test "open gallery after transition from intive to room", %{conn: conn, state: state} do
      %{}
      |> create_users(2)
    end

    defp create_users(conn, number) do
      Enum.reduce(1..number, %{conn: conn, users: []}, fn _, acc ->
        {conn, user} = IndexTest.create_user(acc.conn)
        Map.put(acc, :users, [user | acc.users])
      end)
    end
  
    defp create_initial_state(_) do
      # Set up the initial state by creating users
      {conn, users_state} = create_users(2)
      %{conn: conn, state: users_state}
    end
  end
end
