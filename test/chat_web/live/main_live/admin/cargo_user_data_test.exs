defmodule ChatWebTest.MainLive.Admin.CargoUserDataTest do
  use ChatWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import LiveIsolatedComponent

  alias Chat.Actor
  alias Chat.User
  alias ChatWeb.MainLive.Admin.CargoUserData

  test "name shorter than 2 chars keeps Create disabled" do
    view = mount_component(nil)

    view |> form("#cargo_user_form", user: %{name: " a "}) |> render_change()
    assert has_element?(view, "#cargo_user_form button[type=submit][disabled]")

    view |> form("#cargo_user_form", user: %{name: "ab"}) |> render_change()
    refute has_element?(view, "#cargo_user_form button[type=submit][disabled]")
  end

  test "create asks the panel to create the cargo user with its keys file" do
    view = mount_component(nil)

    view |> form("#cargo_user_form", user: %{name: "Cargo Bot"}) |> render_submit()

    assert_handle_info(
      view,
      {:admin,
       {:create_cargo_user, {identity, content, %{client_name: "Cargo Bot.data"} = entry}}}
    )

    assert identity.name == "Cargo Bot"
    assert entry.client_size == byte_size(content)
    assert %{me: %{name: "Cargo Bot"}} = Actor.from_encrypted_json(content, "")
  end

  test "uploading a valid keys file creates the cargo user from it" do
    identity = User.login("Uploaded Cargo")
    content = identity |> Actor.new([], %{}) |> Actor.to_encrypted_json("")
    view = mount_component(nil, handle_info: &store_created_cargo_user/2)

    upload = keys_upload(view, content)
    view |> form("#upload-cargo-user") |> render_change()
    render_upload(upload, "cargo.data", 50)
    refute_handle_info(view, {:admin, {:create_cargo_user, _}}, 100)

    render_upload(upload, "cargo.data", 50)

    assert_handle_info(view, {:admin, {:create_cargo_user, {uploaded, ^content, _entry}}})
    assert uploaded == identity
    assert has_element?(view, ".t-download-key")
  end

  test "uploading broken keys shows an error" do
    for content <- ["not a keys file", "[[\"broken"] do
      view = mount_component(nil)

      view |> keys_upload(content) |> render_upload("cargo.data")

      assert has_element?(view, "p", "Keys are invalid or broken")
      refute_handle_info(view, {:admin, {:create_cargo_user, _}}, 100)
    end
  end

  test "existing cargo user can download its keys" do
    view = mount_component(User.login("Existing Cargo"))

    assert has_element?(view, ".t-download-key")
    refute has_element?(view, "#cargo_user_form")

    view |> element("button[phx-click=backup-keys]") |> render_click()

    assert_push_event(view, "chat:redirect", %{url: "/get/backup/" <> key})
    assert key != ""
  end

  # Helpers

  defp mount_component(cargo_user, opts \\ []) do
    {:ok, view, _} =
      live_isolated_component(
        CargoUserData,
        Keyword.put(opts, :assigns, %{id: :cargo_user_data, cargo_user: cargo_user})
      )

    view
  end

  # What the admin panel does: store the user and pass it back to the component
  defp store_created_cargo_user({:admin, {:create_cargo_user, {identity, _, _}}}, socket),
    do: {:noreply, Phoenix.Component.assign(socket, :cargo_user, identity)}

  defp keys_upload(view, content) do
    file_input(view, "#upload-cargo-user", :config, [
      %{name: "cargo.data", content: content, type: "text/plain"}
    ])
  end
end
