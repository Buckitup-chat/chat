defmodule Chat.ImagesTest do
  use ExUnit.Case, async: false

  alias Chat.Images

  test "image should be returned" do
    {key, secret} = Images.add("image")

    image = Images.get(key, secret)

    assert image == "image"
  end
end
