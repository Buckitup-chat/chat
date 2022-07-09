defmodule Chat.Ordering do
  @moduledoc "Ordering context"

  alias Chat.Db
  alias Chat.Ordering.Counters

  def next(key) do
    key |> get_or_init(&next_counter/1)
  end

  def last(key) do
    key |> get_or_init(&last_counter/1)
  end

  defp get_or_init(key, getter_fn) do
    case getter_fn.(key) do
      nil ->
        key
        |> tap(&init_counter/1)
        |> then(getter_fn)

      value ->
        value
    end
  end

  defp last_counter(key), do: Counters.get(key)
  defp next_counter(key), do: Counters.next(key)

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

  defp min_key({a}), do: {a, 0, 0}
  defp min_key({a, b}), do: {a, b, 0, 0}
  defp max_key({a}), do: {a, nil, 0}
  defp max_key({a, b}), do: {a, b, nil, 0}

  defp init_fresh_counter(key) do
    Counters.set(key, 0)
  end

  defp restore_counter(key, value) do
    Counters.set(key, value)
  end
end
