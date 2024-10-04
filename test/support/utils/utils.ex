defmodule ChatSupport.Utils do
  @moduledoc "Miscellaneous utils"

  @doc """
  Waits till `action_fn` return something truthy.
  Timeouts when `opts[:time]` passed.
  Rechecks every `opts[:step]` milliseconds

  Returns result of `action_fn` or `:timeout`
  """
  def await_till(action_fn, opts \\ []) do
    time = opts[:time] || 2000
    step = opts[:step] || 500

    cond do
      time < 0 ->
        :timeout

      x = action_fn.() ->
        x

      true ->
        Process.sleep(step)
        await_till(action_fn, time: time - step, step: step)
    end
  end
end
