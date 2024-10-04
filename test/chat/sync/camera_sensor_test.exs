defmodule Chat.Sync.CameraSensorTest do
  use ExUnit.Case

  alias Chat.Sync.Camera.Sensor

  # todo: implement

  test "get ONVIF image", do: :todo
  test "get full url", do: :todo

  test "return error with 'http://' url" do
    assert {:error, _} = Sensor.get_image("http://")
    assert {:error, _} = Sensor.get_image("http://pp.")
  end
end
