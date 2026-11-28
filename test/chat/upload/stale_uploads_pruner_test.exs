defmodule Chat.Upload.StaleUploadsPrunerTest do
  use ExUnit.Case, async: true, group: :cubdb

  alias Chat.{ChunkedFiles, ChunkedFilesBroker}
  alias Chat.Db.ChangeTracker
  alias Chat.Upload.{StaleUploadsPruner, Upload, UploadIndex, UploadStatus, UploadSupervisor}

  @day_in_seconds 24 * 60 * 60

  describe "maybe_set_timestamp/1" do
    setup do
      start_supervised(StaleUploadsPruner)

      :ok
    end

    test "prunes old uploads" do
      timestamp = DateTime.to_unix(DateTime.utc_now()) - @day_in_seconds - 1
      old_key = UUID.uuid4()
      old_upload = %Upload{encrypted_secret: "1234", timestamp: timestamp}
      UploadIndex.add(old_key, old_upload)

      timestamp = DateTime.to_unix(DateTime.utc_now()) - @day_in_seconds + 1
      new_key = UUID.uuid4()
      new_upload = %Upload{encrypted_secret: "1234", timestamp: timestamp}
      UploadIndex.add(new_key, new_upload)

      ChangeTracker.await()

      timestamp = DateTime.to_unix(DateTime.utc_now())
      StaleUploadsPruner.maybe_set_timestamp(timestamp)
      await_prune()

      uploads = UploadIndex.list()
      refute Map.has_key?(uploads, old_key)
      assert Map.has_key?(uploads, new_key)

      # let the monotonic clock age new_upload past one day
      :timer.sleep(3000)
      send(StaleUploadsPruner, :prune)
      await_prune()

      uploads = UploadIndex.list()
      refute Map.has_key?(uploads, old_key)
      refute Map.has_key?(uploads, new_key)
    end

    test "does nothing if the timestamp is already set" do
      timestamp = DateTime.to_unix(DateTime.utc_now()) - @day_in_seconds
      StaleUploadsPruner.maybe_set_timestamp(timestamp)

      timestamp = DateTime.to_unix(DateTime.utc_now()) - @day_in_seconds - 1
      key = UUID.uuid4()
      upload = %Upload{encrypted_secret: "1234", timestamp: timestamp}
      UploadIndex.add(key, upload)
      ChangeTracker.await()

      timestamp = DateTime.to_unix(DateTime.utc_now())
      StaleUploadsPruner.maybe_set_timestamp(timestamp)
      await_prune()

      uploads = UploadIndex.list()
      assert Map.has_key?(uploads, key)
    end

    test "prunes old chunks" do
      key = UUID.uuid4()
      ChunkedFiles.new_upload(key)
      ChunkedFiles.save_upload_chunk(key, {0, 17}, 18, "some part of info ")
      timestamp = DateTime.to_unix(DateTime.utc_now()) - @day_in_seconds - 1
      upload = %Upload{encrypted_secret: "1234", timestamp: timestamp}
      UploadIndex.add(key, upload)
      ChangeTracker.await()

      timestamp = DateTime.to_unix(DateTime.utc_now())
      StaleUploadsPruner.maybe_set_timestamp(timestamp)
      await_prune()

      refute ChunkedFilesBroker.get(key)
      assert ChunkedFiles.size(key) == 0
    end

    test "stops old upload status servers" do
      key = UUID.uuid4()
      timestamp = DateTime.to_unix(DateTime.utc_now()) - @day_in_seconds - 1
      upload = %Upload{encrypted_secret: "1234", timestamp: timestamp}
      UploadIndex.add(key, upload)
      ChangeTracker.await()

      child_spec = UploadStatus.child_spec(key: key, status: :active)
      DynamicSupervisor.start_child(UploadSupervisor, child_spec)

      timestamp = DateTime.to_unix(DateTime.utc_now())
      StaleUploadsPruner.maybe_set_timestamp(timestamp)
      await_prune()

      assert catch_exit(UploadStatus.get(key))
    end
  end

  # Helpers

  # A call is handled only after the pending cast and its prune (handle_continue).
  # The pruner's deletes then go through the write queue, so wait for them too.
  defp await_prune do
    :sys.get_state(StaleUploadsPruner)
    ChangeTracker.await()
  end
end
