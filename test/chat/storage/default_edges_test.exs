defmodule Chat.Storage.DefaultEdgesTest do
  @moduledoc "Only edges read `Chat.Storage.Default`; everything below takes a `%Unit{}` (spec §2.6)."
  use ExUnit.Case, async: true

  @edges ~W[
    lib/chat/storage/default.ex
    lib/chat/db.ex
    lib/chat/debug.ex
    lib/chat/data/file/gc.ex
    lib/chat/data/file/validation.ex
    lib/chat/data/shapes/file_chunk.ex
    lib/chat/network_synchronization/network_synchronization.ex
    lib/chat_web/controllers/file_chunk_controller.ex
    lib/chat_web/controllers/file_chunk_status_controller.ex
  ]

  test "Default is read only at edges" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.reject(&(&1 in @edges or String.starts_with?(&1, "lib/chat/storage/default/")))
      |> Enum.filter(&(File.read!(&1) =~ ~r/\bDefault\.(unit|switch_to)\(/))

    assert offenders == []
  end
end
