defmodule Support.FakeData do
  @moduledoc "Data stubs for tests"
  alias Chat.Messages
  alias Phoenix.LiveView.{UploadEntry, Utils}

  def file do
    key = UUID.uuid4() |> Enigma.hash()
    secret = Enigma.generate_secret()

    %{client_size: 123, client_type: "audio/mp3", client_name: "Some file.ext"}
    |> Messages.File.new(key, secret)
  end

  def image(name) do
    key = UUID.uuid4() |> Enigma.hash()
    secret = Enigma.generate_secret()

    %{client_size: 123, client_type: "image/jpeg", client_name: name}
    |> Messages.File.new(key, secret)
  end

  def upload_entry(uuid) do
    %UploadEntry{
      progress: 0,
      preflighted?: true,
      upload_config: :file,
      upload_ref: Utils.random_id(),
      ref: "898",
      uuid: uuid,
      valid?: true,
      done?: false,
      cancelled?: false,
      client_name: "#{Utils.random_id()}.jpeg",
      client_relative_path: nil,
      client_size: 70,
      client_type: "image/jpeg",
      client_last_modified: nil
    }
  end
end
