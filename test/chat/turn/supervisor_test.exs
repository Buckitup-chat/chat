defmodule Chat.Turn.SupervisorTest do
  use ExUnit.Case, async: false

  alias Chat.Turn.Config

  defp setup_config(overrides) do
    prev_state = :persistent_term.get(Config, nil)

    base = %{
      secret: "test-secret",
      enabled: false,
      public_ip: nil,
      public_ip_tuple: nil,
      realm: "buckitup.test",
      uris: [],
      ttl: 600,
      rate_per_ip_hour: 60
    }

    :persistent_term.put(Config, Map.merge(base, overrides))

    on_exit(fn ->
      if prev_state, do: :persistent_term.put(Config, prev_state)
    end)
  end

  describe "init/1" do
    test "starts with no children when TURN is disabled" do
      setup_config(%{enabled: false})
      assert {:ok, {_, []}} = Chat.Turn.Supervisor.init([])
    end

    test "starts a listener task when TURN is enabled" do
      setup_config(%{enabled: true, public_ip: "203.0.113.1", public_ip_tuple: {203, 0, 113, 1}})
      {:ok, {_, children}} = Chat.Turn.Supervisor.init([])
      assert length(children) == 1
    end
  end
end
