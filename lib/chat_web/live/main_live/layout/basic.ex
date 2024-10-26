defmodule ChatWeb.MainLive.Layout.Basic do
  @moduledoc "Basic layout"
  use ChatWeb, :component

  def loading_screen(assigns) do
    ~H"""
    <img class="vectorGroup bottomVectorGroup" src="/images/bottom_vector_group.svg" />
    <img class="vectorGroup topVectorGroup" src="/images/top_vector_group.svg" />
    <div class="flex flex-col items-center justify-center w-screen h-screen">
      <div class="container unauthenticated z-10">
        <img src="/images/logo.png" />
      </div>
    </div>
    """
  end
end
