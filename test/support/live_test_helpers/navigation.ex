defmodule ChatWeb.LiveTestHelpers.Navigation do
  @moduledoc """
  Clicks through the main LiveView navigation and the room creation form.
  Each function returns the rendered HTML of the click or submit.
  """

  import Phoenix.LiveViewTest

  @doc "Opens the admin panel from the navbar."
  def open_admin_panel(view), do: view |> element(".navbar button", "Admin") |> render_click()

  @doc "Switches the lobby to the rooms tab."
  def open_rooms_tab(view), do: view |> element(".t-rooms", "Rooms") |> render_click()

  @doc "Switches the lobby to the chats tab."
  def open_chats_tab(view), do: view |> element(".t-chats", "Chats") |> render_click()

  @doc "Submits the room creation form with the given name and type."
  def submit_room_form(view, name, type) do
    view
    |> form("#room-create-form", %{"room_input" => %{"name" => name, "type" => type}})
    |> render_submit()
  end
end
