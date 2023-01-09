defmodule Chat.Utils.StorageId do
  @moduledoc "Helper function for storing enrypted content"

  def from_json(json) do
    json
    |> Jason.decode!()
    |> Map.to_list()
    |> List.first()
    |> then(fn {id, secret} -> {id, secret |> Base.url_decode64!()} end)
  end

  def from_json_to_key(json) do
    json
    |> Jason.decode!()
    |> Enum.find_value(fn {key, _} -> key end)
  end

  def to_json({key, secret}) do
    %{key => secret |> Base.url_encode64()}
    |> Jason.encode!()
  end
end
