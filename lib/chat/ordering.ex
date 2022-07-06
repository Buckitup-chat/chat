defmodule Chat.Ordering do
  @moduledoc "Ordering context"

  alias Chat.Db
  alias Chat.Ordering.Counters

  def next(key) do
    case next_counter(key) do
      nil ->
        key
        |> tap(&init_counter/1)
        |> next_counter()

      next ->
        next
    end
  end

  defp next_counter(key) do
    Counters.next(key)
  end

  defp init_counter(key) do
    case get_last_in_db(key) do
      nil -> init_fresh_counter(key)
      {key, counter} -> restore_counter(key, counter)
    end
  end

  defp get_last_in_db(key) do
    case Db.get_max_one(min_key(key), max_key(key)) do
      [] -> nil
      [{{a, b, counter, _}, _}] -> {{a, b}, counter}
    end
  end

  defp min_key({a, b}), do: {a, b, 0, 0}
  defp max_key({a, b}), do: {a, b, nil, 0}

  defp init_fresh_counter(key) do
    Counters.set(key, 0)
  end

  defp restore_counter(key, value) do
    Counters.set(key, value)
  end
end
