defmodule Proxy.Api do
  @moduledoc "Proxy API. For server controller"

  @known_atoms %{
    users: :"users\0"
  }
  def known_atoms(), do: @known_atoms

  def select_data(args) do
    args
    |> case do
      binary when is_binary(binary) -> Proxy.Serialize.deserialize(binary)
      x -> x
    end
    |> Map.new()
    |> case do
      %{min: min, max: max, amount: amount} ->
        getter =
          min
          |> elem(0)
          |> choose_getter()

        getter.({min, max}, amount)
        |> Enum.to_list()

      _ ->
        :wrong_args
    end
    |> Proxy.Serialize.serialize()
  catch
    _, _ -> :wrong_args |> Proxy.Serialize.serialize()
  end

  defp choose_getter(slug) do
    case slug do
      :users -> &Chat.Db.values/2
      _ -> &Chat.Db.select/2
    end
  end
end
