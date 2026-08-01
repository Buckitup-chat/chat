defmodule ChatWeb.ElectricLive.Components do
  @moduledoc false

  use Phoenix.Component

  attr :rating, :integer, required: true

  def stars(assigns) do
    ~H"""
    <div class="flex gap-0.5">
      <span :for={i <- 1..5} class={if i <= @rating, do: "text-yellow-400", else: "text-gray-300"}>
        &#9733;
      </span>
    </div>
    """
  end
end
