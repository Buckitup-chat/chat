defmodule Chat.ChunkedFilesMultisecretTest do
  use ExUnit.Case

  alias Chat.ChunkedFiles
  alias Chat.ChunkedFilesMultisecret
  alias Chat.Db
  alias Chat.Db.ChangeTracker

  @chunk_size Application.compile_env(:chat, :file_chunk_size)
  @hundred_chunks_size 100 * @chunk_size

  describe "multi-secret for files up to 1GB" do
    setup do
      generate(@hundred_chunks_size - 100)
    end

    test "should not generate no additional secrets", %{file_key: file_key} do
      assert nil == Db.get({:file_secrets, file_key})
    end

    test "should return initial secret", %{file_key: file_key, initial_secret: initial_secret} do
      assert initial_secret == ChunkedFilesMultisecret.get_secret(file_key, 0, initial_secret)
    end
  end

  describe "multi-secret for over 1GB" do
    setup do
      generate(@hundred_chunks_size * 3 + 100)
    end

    test "should generate additional secrets", %{
      file_key: file_key,
      initial_secret: initial_secret
    } do
      additional_secrets = Db.get({:file_secrets, file_key})

      secret =
        ChunkedFilesMultisecret.get_secret(file_key, @hundred_chunks_size + 100, initial_secret)

      assert 96 == additional_secrets |> byte_size()
      assert 32 == secret |> byte_size()
      assert secret != initial_secret

      assert secret ==
               additional_secrets |> :binary.part({0, 32}) |> Enigma.decipher(initial_secret)
    end
  end

  def generate(file_size) do
    file_key = UUID.uuid4() |> Enigma.hash()
    initial_secret = ChunkedFiles.new_upload(file_key)
    ChunkedFilesMultisecret.generate(file_key, file_size, initial_secret)
    ChangeTracker.await()

    [file_key: file_key, initial_secret: initial_secret]
  end
end
