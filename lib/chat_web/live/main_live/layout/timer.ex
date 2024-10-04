defmodule ChatWeb.MainLive.Layout.Timer do
  @moduledoc "Timer for Cargo sync and USB drive dump rooms"

  use ChatWeb, :component

  attr :timer, :integer, required: true, doc: "time remaining in seconds"

  def timer(%{timer: timer} = assigns) do
    minutes = "#{div(timer, 60)}"

    seconds =
      timer
      |> rem(60)
      |> formatted_seconds()

    timer = minutes <> ":" <> seconds

    assigns = assign(assigns, :timer, timer)

    ~H"""
    <div class="w-10 ml-1 text-white/90"><%= @timer %></div>
    """
  end

  defp formatted_seconds(seconds) when seconds < 10, do: "0#{seconds}"
  defp formatted_seconds(seconds), do: "#{seconds}"
end
