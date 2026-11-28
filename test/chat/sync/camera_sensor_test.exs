defmodule Chat.Sync.CameraSensorTest do
  use ExUnit.Case, async: true

  import Support.Rewire

  alias Chat.Sync.Camera.Sensor

  @image "jpeg-bytes"
  @snapshot_url "http://cam.local/onvif/snapshot.jpg"

  defmodule FakeTesla do
    def client(middleware, adapter) do
      send(self(), {:tesla_client, middleware, adapter})
      :client
    end

    def get(:client, url) do
      send(self(), {:tesla_get, url})
      Process.get(:tesla_reply)
    end
  end

  defmodule ProfilesOk do
    def request(url, auth_type) do
      send(self(), {:get_profiles, url, auth_type})
      [{:ok, %{reference_token: "profile_1"}}]
    end
  end

  defmodule ProfilesNone do
    def request(_url, _auth_type), do: []
  end

  defmodule SnapshotOk do
    def request(url, profiles) do
      send(self(), {:get_snapshot_uri, url, profiles})
      {:ok, "http://cam.local/onvif/snapshot.jpg"}
    end
  end

  describe "get_image/1 URL validation" do
    test "rejects url without hostname" do
      assert {:error, "URL invalid (no hostname)"} = Sensor.get_image("http://")
    end

    test "treats unresolvable host-only url as failed ONVIF lookup" do
      assert {:error, "Error getting ONVIF endpoint"} =
               rewire(Sensor, GetProfiles: ProfilesNone).get_image("http://pp.")
    end

    test "rejects unknown scheme" do
      assert {:error, "URL invalid (no known scheme)"} =
               Sensor.get_image("ftp://cam.local/shot.jpg")
    end
  end

  describe "get_image/1 by full url" do
    test "returns image with its content type" do
      reply_with({:ok, %{status: 200, headers: [{"content-type", "image/png"}], body: @image}})

      assert {:ok, {"image/png", @image}} = sensor().get_image("http://cam.local/shot.png")
      assert_received {:tesla_get, "http://cam.local/shot.png"}
      assert_received {:tesla_client, [{Tesla.Middleware.Timeout, timeout: 1000}], _}
    end

    test "defaults content type when header is missing" do
      reply_with({:ok, %{status: 200, headers: [{"x-other", "1"}], body: @image}})

      assert {:ok, {"application/octet-stream", @image}} =
               sensor().get_image("http://cam.local/shot")
    end

    test "uses digest auth and strips credentials from the url" do
      reply_with({:ok, %{status: 200, headers: [], body: @image}})

      assert {:ok, _} = sensor().get_image("http://admin:secret@cam.local/shot.jpg")
      assert_received {:tesla_get, "http://cam.local/shot.jpg"}
      assert_received {:tesla_client, middleware, _}

      assert {Tesla.Middleware.DigestAuth, %{username: "admin", password: "secret"}} in middleware
    end

    test "reports non-200 status" do
      reply_with({:ok, %{status: 401, headers: [], body: ""}})

      assert {:error, "Error getting image [401]"} = sensor().get_image("http://cam.local/shot")
    end

    test "reports request failure" do
      reply_with({:error, :timeout})

      assert {:error, "Error getting image"} = sensor().get_image("http://cam.local/shot")
    end
  end

  describe "get_image/1 via ONVIF" do
    test "fetches snapshot from ONVIF endpoint for host-only url" do
      reply_with({:ok, %{status: 200, headers: [{"content-type", "image/jpeg"}], body: @image}})

      assert {:ok, {"image/jpeg", @image}} = onvif_sensor().get_image("http://cam.local")
      assert_received {:get_profiles, "http://cam.local", :no_auth}
      assert_received {:get_snapshot_uri, "http://cam.local", ["profile_1"]}
      assert_received {:tesla_get, @snapshot_url}
    end

    test "uses digest auth for ONVIF when credentials are given" do
      reply_with({:ok, %{status: 200, headers: [], body: @image}})

      assert {:ok, _} = onvif_sensor().get_image("http://admin:secret@cam.local/")
      assert_received {:get_profiles, "http://admin:secret@cam.local/", :digest_auth}
    end

    test "reports missing ONVIF profiles" do
      assert {:error, "Error getting ONVIF endpoint"} =
               rewire(Sensor, GetProfiles: ProfilesNone, Tesla: FakeTesla).get_image(
                 "http://cam.local/"
               )

      refute_received {:tesla_get, _}
    end
  end

  # Helpers

  defp sensor, do: rewire(Sensor, Tesla: FakeTesla)

  defp onvif_sensor,
    do: rewire(Sensor, GetProfiles: ProfilesOk, GetSnapshotUri: SnapshotOk, Tesla: FakeTesla)

  defp reply_with(reply), do: Process.put(:tesla_reply, reply)
end
