defmodule Support.RetryHelper do
  @moduledoc """
  Test helper enabling assertation retry until it starts being true
  or the it times out. In case assertation is false it tries again in 10 ms.
  """

  def retry_until(0, fun), do: fun.()

  def retry_until(timeout, fun) do
    fun.()
  rescue
    ExUnit.AssertionError ->
      :timer.sleep(10)
      retry_until(max(0, timeout - 10), fun)
  end
end
