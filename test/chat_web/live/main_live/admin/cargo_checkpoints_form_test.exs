defmodule ChatWebTest.MainLive.Admin.CargoCheckpointsFormTest do
  # Cargo settings live in the global AdminDb
  use ChatWeb.ConnCase, async: false
  import Phoenix.LiveView, only: [send_update: 3]
  import Phoenix.LiveViewTest
  import LiveIsolatedComponent

  alias Chat.Admin.CargoSettings
  alias Chat.AdminRoom
  alias Chat.Card
  alias Chat.User
  alias Chat.User.UsersBroker
  alias ChatWeb.MainLive.Admin.CargoCheckpointsForm

  setup do
    original = AdminRoom.get_cargo_settings()
    :ok = AdminRoom.store_cargo_settings(%CargoSettings{checkpoints: []})
    on_exit(fn -> AdminRoom.store_cargo_settings(original) end)

    [first, second] =
      for name <- ["Checkpoint First", "Checkpoint Second"] do
        name |> User.login() |> tap(&UsersBroker.put/1) |> Card.from_identity()
      end

    [first: first, second: second]
  end

  test "selecting another user enables Add, adding stores the checkpoint", ctx do
    view = mount_form()

    assert button_disabled?(view, "Add")
    assert button_disabled?(view, "Remove")

    view |> user_item("rest", ctx.first) |> render_click()
    assert has_element?(view, user_selector("rest", ctx.first) <> ".selected-user")
    refute button_disabled?(view, "Add")

    view |> element(".t-buttons button", "Add") |> render_click()

    assert_handle_info(view, :update_cargo_settings)
    assert checkpoints() == [ctx.first]
    assert has_element?(view, user_selector("checkpoints", ctx.first))
    refute has_element?(view, user_selector("rest", ctx.first))
  end

  test "removing the only checkpoint clears the selection", ctx do
    store_checkpoints([ctx.first])
    view = mount_form()

    view |> user_item("checkpoints", ctx.first) |> render_click()
    refute button_disabled?(view, "Remove")

    view |> element(".t-buttons button", "Remove") |> render_click()

    assert_handle_info(view, :update_cargo_settings)
    assert checkpoints() == []
    refute has_element?(view, ".selected-user")
    assert button_disabled?(view, "Remove")
  end

  test "removing a checkpoint selects the next one", ctx do
    store_checkpoints([ctx.first, ctx.second])
    view = mount_form()

    remove(view, ctx.first)

    assert checkpoints() == [ctx.second]
    assert has_element?(view, user_selector("checkpoints", ctx.second) <> ".selected-user")
  end

  test "removing the last checkpoint selects the previous one", ctx do
    store_checkpoints([ctx.first, ctx.second])
    view = mount_form()

    remove(view, ctx.second)

    assert checkpoints() == [ctx.first]
    assert has_element?(view, user_selector("checkpoints", ctx.first) <> ".selected-user")
  end

  test "move_user moves users between the lists", ctx do
    view = mount_form()

    view |> move_user("rest", ctx.second)
    assert checkpoints() == [ctx.second]

    view |> move_user("checkpoints", ctx.second)
    assert checkpoints() == []
    assert has_element?(view, user_selector("rest", ctx.second))
  end

  test "refresh re-reads the users and resets the selection", ctx do
    view = mount_form()
    view |> user_item("rest", ctx.first) |> render_click()

    newcomer =
      "Checkpoint Newcomer" |> User.login() |> tap(&UsersBroker.put/1) |> Card.from_identity()

    refute has_element?(view, user_selector("rest", newcomer))

    send_update(view.pid, CargoCheckpointsForm, id: :cargo_checkpoints_form, action: :refresh)

    refute has_element?(view, ".selected-user")
    assert has_element?(view, user_selector("rest", newcomer))
  end

  test "other updates keep the selection", ctx do
    view = mount_form()
    view |> user_item("rest", ctx.first) |> render_click()

    send_update(view.pid, CargoCheckpointsForm, id: :cargo_checkpoints_form, other: :value)

    assert has_element?(view, user_selector("rest", ctx.first) <> ".selected-user")
  end

  # Helpers

  defp mount_form do
    {:ok, view, _} =
      live_isolated_component(CargoCheckpointsForm, assigns: %{id: :cargo_checkpoints_form})

    view
  end

  defp store_checkpoints(cards) do
    :ok = AdminRoom.store_cargo_settings(%CargoSettings{checkpoints: cards})
  end

  defp checkpoints, do: AdminRoom.get_cargo_settings().checkpoints

  defp remove(view, card) do
    view |> user_item("checkpoints", card) |> render_click()
    view |> element(".t-buttons button", "Remove") |> render_click()
  end

  defp user_item(view, type, card), do: element(view, user_selector(type, card))

  defp user_selector(type, card),
    do: "#users-#{type} li[phx-value-pub-key=#{hex(card)}]"

  # Pushed by the draggable-checkpoints JS hook, so no element carries the event
  defp move_user(view, type, card) do
    view
    |> with_target("section[data-phx-component]")
    |> render_hook("move_user", %{"pub_key" => hex(card), "type" => type})
  end

  defp button_disabled?(view, text),
    do: has_element?(view, ".t-buttons button[disabled]", text)

  defp hex(card), do: Base.encode16(card.pub_key, case: :lower)
end
