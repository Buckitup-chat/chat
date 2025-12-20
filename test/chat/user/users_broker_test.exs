defmodule Chat.User.UsersBrokerTest do
  use ChatWeb.DataCase, async: false
  alias Chat.Card
  alias Chat.User.UsersBroker

  setup do
    # Start the UsersBroker process
    start_supervised!({UsersBroker, name: :test_users_broker})
    :ok
  end

  describe "search functionality" do
    test "handles nil user names when searching" do
      # Create test users with different name scenarios
      users = [
        %Card{pub_key: "1", name: "John Doe"},
        # User with nil name
        %Card{pub_key: "2", name: nil},
        %Card{pub_key: "3", name: "Alice Smith"},
        %Card{pub_key: "4", name: "Bob Johnson"},
        # Another user with nil name
        %Card{pub_key: "5", name: nil}
      ]

      # Add users to the broker and wait for each to be processed
      for user <- users do
        put_user(user)
      end

      await_users_set()

      # Test search with a term that should match one user
      assert list_users("doe") |> Enum.find(&(&1.pub_key == "1"))

      # Test search with a term that should match one specific user
      assert list_users("alice") |> Enum.find(&(&1.pub_key == "3"))

      # Test search with a term that should match another specific user
      assert list_users("bob") |> Enum.find(&(&1.pub_key == "4"))

      # Test that empty search returns all users with non-nil names
      results = list_users("") |> Enum.filter(&(&1 in users)) |> Enum.sort_by(& &1.name)
      # Only users with non-nil names
      assert length(results) == 3

      assert [
               %Card{name: "Alice Smith"},
               %Card{name: "Bob Johnson"},
               %Card{name: "John Doe"}
             ] = results

      # Test that users with nil names don't cause errors with any search term
      assert [] == list_users("nonexistent")
    end
  end

  defp broker_pid, do: Process.whereis(:test_users_broker)

  defp put_user(user) do
    GenServer.cast(broker_pid(), {:put, user})
  end

  defp await_users_set do
    # Wait a bit to ensure the cast is processed
    Process.sleep(10)
  end

  defp list_users(search_term) do
    GenServer.call(broker_pid(), {:list, search_term})
  end
end
