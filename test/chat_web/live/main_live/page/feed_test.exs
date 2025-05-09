defmodule ChatWeb.MainLive.Page.FeedTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ChatWeb.LiveTestHelpers
  import Rewire

  alias Chat.Card
  alias Chat.Identity

  # Define mock modules for Rewire
  defmodule UserMock do
    def by_id(_id) do
      %{
        name: "Test User",
        pub_key: <<1, 2, 3, 4, 5>>
      }
    end
  end

  defmodule RoomsMock do
    def get(_id) do
      %{name: "Test Room"}
    end
  end

  defmodule LogMock do
    # The Feed component calls humanize_action with just the action type (atom)
    def humanize_action(:create_room) do
      "created room"
    end

    def humanize_action(:send_message) do
      "sent a message"
    end

    def humanize_action(:join_room) do
      "joined a room"
    end

    # Implement list functions for load_actions and load_more
    def list do
      # Return a tuple with log items and a till value
      {[
         {"uuid1", <<1, 2, 3, 4, 5>>, {System.os_time(:second), :create_room}},
         {"uuid2", <<1, 2, 3, 4, 5>>, {System.os_time(:second), :send_message}}
       ], 100}
    end

    def list(_since) do
      # Return a tuple with log items and a till value for pagination
      {[
         {"uuid3", <<1, 2, 3, 4, 5>>, {System.os_time(:second), :join_room}}
       ], 50}
    end
  end

  describe "Feed component" do
    setup [:prepare_view, :setup_feed_data]

    test "action renders correctly for action with options", %{test_user: test_user} do
      # Create test data
      action = {:create_room, to: test_user.pub_key, room: "room1"}

      # Rewire the component with mocked dependencies
      rewired_feed =
        rewire(ChatWeb.MainLive.Page.Feed, [
          {Chat.User, UserMock},
          {Chat.Rooms, RoomsMock},
          {Chat.Log, LogMock}
        ])

      # Render the action component
      html =
        render_component(&rewired_feed.action/1, %{
          action: action
        })

      # Verify the rendered HTML
      assert html =~ "created room"
      assert html =~ "Test User"
      assert html =~ "Test Room"
    end

    test "action renders correctly for simple action" do
      # Create test data
      action = {:create_room}

      # Rewire the component with mocked dependencies
      rewired_feed =
        rewire(ChatWeb.MainLive.Page.Feed, [
          {Chat.Log, LogMock}
        ])

      # Render the action component
      html =
        render_component(&rewired_feed.action/1, %{
          action: action
        })

      # Verify the rendered HTML
      assert html =~ "created room"
    end
  end

  # Helper functions
  defp setup_feed_data(%{conn: _conn}) do
    # Create test user
    test_identity = Identity.create("Test User")
    test_card = Card.from_identity(test_identity)

    # Create test log items
    log_items = [
      {"uuid1", test_card.pub_key, {:os.system_time(:second), :create_room}},
      {"uuid2", test_card.pub_key, {:os.system_time(:second), :send_message, to: "user2"}},
      {"uuid3", test_card.pub_key, {:os.system_time(:second), :join_room, room: "room1"}}
    ]

    till = 100

    # Create more test log items for pagination
    more_items = [
      {"uuid4", test_card.pub_key, {:os.system_time(:second), :create_room}},
      {"uuid5", test_card.pub_key, {:os.system_time(:second), :send_message, to: "user3"}}
    ]

    more_till = 50

    [
      test_user: test_card,
      log_items: log_items,
      till: till,
      more_items: more_items,
      more_till: more_till
    ]
  end
end
