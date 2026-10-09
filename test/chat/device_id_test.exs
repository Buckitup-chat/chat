defmodule Chat.DeviceIdTest do
  use ExUnit.Case, async: false

  alias Chat.DeviceId

  setup do
    endpoint_config = Application.get_env(:chat, ChatWeb.Endpoint)
    device_id_module = Application.get_env(:chat, :device_id_module)

    on_exit(fn ->
      if endpoint_config,
        do: Application.put_env(:chat, ChatWeb.Endpoint, endpoint_config),
        else: Application.delete_env(:chat, ChatWeb.Endpoint)

      if device_id_module,
        do: Application.put_env(:chat, :device_id_module, device_id_module),
        else: Application.delete_env(:chat, :device_id_module)
    end)

    :ok
  end

  describe "Default implementation" do
    test "returns Server_<domain> when endpoint host is configured" do
      set_endpoint_host("example.com")

      assert "Server_example_com" = DeviceId.Default.id()
    end

    test "domain id is a single lowercase scope segment" do
      set_endpoint_host("Chat.BuckitUp.xyz")

      assert "Server_chat_buckitup_xyz" = id = DeviceId.Default.id()
      assert ["device", ^id, "admin"] = String.split("device.#{id}.admin", ".")
    end

    test "falls back to Localhost_<mac> when no domain" do
      set_endpoint_host("localhost")

      result = DeviceId.Default.id()
      assert String.starts_with?(result, "Localhost_")
      mac = String.replace_prefix(result, "Localhost_", "")
      assert String.length(mac) == 12
      assert String.match?(mac, ~r/^[0-9a-f]{12}$/)
    end

    test "skips empty host" do
      set_endpoint_host("")

      refute DeviceId.Default.id() |> String.starts_with?("Server_")
    end

    defp set_endpoint_host(host) do
      Application.put_env(:chat, ChatWeb.Endpoint, url: [host: host])
    end
  end

  describe "id/0 dispatch" do
    test "uses configured module" do
      Application.put_env(:chat, :device_id_module, Chat.DeviceId.Default)

      assert is_binary(DeviceId.id())
    end

    test "defaults to Default when no module configured" do
      Application.delete_env(:chat, :device_id_module)

      assert is_binary(DeviceId.id())
    end
  end
end
