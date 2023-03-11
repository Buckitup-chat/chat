defmodule Tools.GenServerHelpers do
  @moduledoc """
  Common functions to make GenServer response
  """

  def ok(state), do: {:ok, state}

  def ok_continue(state, msg), do: {:ok, state, {:continue, msg}}
  def noreply(state), do: {:noreply, state}
  def reply(state, result), do: {:reply, result, state}

  def noreply_continue(state, continue_message),
    do: {:noreply, state, {:continue, continue_message}}

  def reply_continue(state, result, continue_message),
    do: {:reply, result, state, {:continue, continue_message}}
end
