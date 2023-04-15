defmodule Chat.Db.ChangeTracker.Tracking do
  @moduledoc """
  Tracking logic
  """
  # use ExUnit.Case
  require Record

  Record.defrecordp(:tracker,
    next_id: 1,
    keys: %{},
    items: %{}
  )

  def new do
    tracker()
  end

  def add_await(state, key, from, expiration) do
    add_action(
      state,
      key,
      {
        fn -> GenServer.reply(from, :done) end,
        fn -> GenServer.reply(from, :expired) end
      },
      expiration
    )
  end

  def add_promise(state, key, actions, expiration) do
    state
    |> add_action(key, actions, expiration)
  end

  def check_written(state, time, keys \\ []) do
    state
    |> extract_keys_found(keys)
    |> extract_expired(time)
    |> cleanup()
  end

  def extract_keys_found(
        tracker(keys: keys, items: items) = state,
        found_keys
      ) do
    ids =
      keys
      |> Map.take(found_keys)
      |> Map.values()
      |> List.flatten()

    items
    |> Map.take(ids)
    |> Map.values()
    |> Enum.each(fn {_, _, {ok_fn, _}} ->
      Task.Supervisor.start_child(Chat.Db.ChangeTracker.Tasks, ok_fn)
    end)

    state
    |> tracker(
      keys: keys |> Map.drop(found_keys),
      items: items |> Map.drop(ids)
    )
  end

  def extract_expired(tracker(keys: keys, items: items) = state, now) do
    {ids, changes} =
      items
      |> Enum.filter(fn {_, {_, expiration, _}} -> expiration <= now end)
      |> Enum.map(fn {id, {key, _, {_, exp_fn}}} ->
        Task.Supervisor.start_child(Chat.Db.ChangeTracker.Tasks, exp_fn)
        {id, {id, key}}
      end)
      |> Enum.reduce({[], []}, fn {id, change}, {ids, changes} ->
        {[id | ids], [change | changes]}
      end)

    # assert [] == changes,
    #        "test should not rely on ChangeTracker expiration\nchanges: " <>
    #          inspect(changes, pretty: true)

    # <>
    #    inspect(
    #      Chat.Db.select({{:rooms, 0}, {:rooms1, 0}}, 100)
    #      |> Enum.to_list(),
    #      pretty: true
    #    )

    new_keys =
      changes
      |> Enum.reduce(keys, fn {id, key}, acc ->
        Map.update!(acc, key, &List.delete(&1, id))
      end)

    state
    |> tracker(
      keys: new_keys,
      items: items |> Map.drop(ids)
    )
  end

  def cleanup(tracker(keys: keys) = state) do
    new_keys =
      keys
      |> Map.reject(fn {_, v} -> v == [] end)

    state
    |> tracker(keys: new_keys)
  end

  defp add_action(
         tracker(next_id: id, keys: keys, items: items) = state,
         key,
         actions,
         expiration
       ) do
    new_keys = Map.update(keys, key, [id], fn list -> [id | list] end)
    item = {key, expiration, actions}

    state
    |> tracker(next_id: id + 1, keys: new_keys, items: items |> Map.put(id, item))
  end
end
