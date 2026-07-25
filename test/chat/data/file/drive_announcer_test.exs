defmodule Chat.Data.File.DriveAnnouncerTest do
  use ChatWeb.DataCase, async: false, shared_sandbox: true

  alias Chat.Data.File.DriveAnnouncer

  @topic "chunk_pipeline"

  setup do
    Phoenix.PubSub.subscribe(Chat.PubSub, @topic)
    :ok
  end

  describe "init/1" do
    test "broadcasts :drive_mounted with the PG system identifier" do
      {:ok, pid} = DriveAnnouncer.start_link(repo: Chat.Repo)

      assert_receive {:chunk_pipeline, {:drive_mounted, system_id}}
      assert is_binary(system_id)
      assert String.length(system_id) > 0

      GenServer.stop(pid)
    end

    test "returns :ignore when repo is nil" do
      assert :ignore = DriveAnnouncer.start_link(repo: nil)
    end
  end

  describe "terminate/2" do
    test "broadcasts :drive_unmounted on stop" do
      {:ok, pid} = DriveAnnouncer.start_link(repo: Chat.Repo)
      assert_receive {:chunk_pipeline, {:drive_mounted, system_id}}

      GenServer.stop(pid)

      assert_receive {:chunk_pipeline, {:drive_unmounted, ^system_id}}
    end
  end
end
