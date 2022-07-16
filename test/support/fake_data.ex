defmodule Support.FakeData do
  @moduledoc "Data stubs for tests"
  alias Chat.Messages

  def file do
    key = UUID.uuid4()
    secret = "12312414132341"

    %{client_size: 123, client_type: "audio/mp3", client_name: "Some file.ext"}
    |> Messages.File.new(key, secret)
  end

  def image(name) do
    key = UUID.uuid4()
    secret = "12312414132341"

    %{client_size: 123, client_type: "image/jpeg", client_name: name}
    |> Messages.File.new(key, secret)
  end
end
