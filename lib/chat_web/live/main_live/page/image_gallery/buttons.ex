defmodule ChatWeb.MainLive.Page.ImageGallery.Buttons do
  @moduledoc """
  Image gallery controls: the back button of the top panel and the prev/next arrows.

  Part of the `ChatWeb.MainLive.Page.ImageGallery` namespace.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  def back_button(assigns) do
    ~H"""
    <div id="backBtn" class="items-center">
      <button
        class="text-white flex z-20"
        phx-target={@target}
        phx-click={
          JS.push("close")
          |> JS.remove_class("hidden", to: "#chatContent")
          |> JS.add_class("hidden", to: "#imageGallery")
        }
      >
        <div class="flex pl-2">
          <svg
            class="relative top-1"
            xmlns="http://www.w3.org/2000/svg"
            width="16"
            height="16"
            fill="white"
            viewBox="0 0 24 24"
          >
            <path d="M16.67 0l2.83 2.829-9.339 9.175 9.339 9.167-2.83 2.829-12.17-11.996z" />
          </svg>
          <p>&nbsp;Back</p>
        </div>
      </button>
    </div>
    """
  end

  def prev_button(assigns) do
    ~H"""
    <button
      id="prev"
      class={(@enabled && "z-10") || "invisible"}
      phx-target={@target}
      phx-click={
        JS.push("switch-prev")
        |> JS.add_class("hidden", to: "#prev")
        |> JS.add_class("hidden", to: "#next")
        |> JS.add_class("hidden", to: "#galleryImage")
        |> JS.remove_class("hidden", to: "#galleryImagePreloader")
      }
    >
      <svg
        class="a-outline"
        xmlns="http://www.w3.org/2000/svg"
        width="24"
        height="24"
        fill="white"
        viewBox="0 0 24 24"
      >
        <path d="M16.67 0l2.83 2.829-9.339 9.175 9.339 9.167-2.83 2.829-12.17-11.996z" />
      </svg>
    </button>
    """
  end

  def next_button(assigns) do
    ~H"""
    <button
      id="next"
      class={(@enabled && "z-10") || "invisible"}
      phx-click={
        JS.push("switch-next")
        |> JS.add_class("hidden", to: "#next")
        |> JS.add_class("hidden", to: "#prev")
        |> JS.add_class("hidden", to: "#galleryImage")
        |> JS.remove_class("hidden", to: "#galleryImagePreloader")
      }
      phx-target={@target}
    >
      <svg
        class="a-outline"
        xmlns="http://www.w3.org/2000/svg"
        width="24"
        height="24"
        fill="white"
        viewBox="0 0 24 24"
      >
        <path d="M5 3l3.057-3 11.943 12-11.943 12-3.057-3 9-9z" />
      </svg>
    </button>
    """
  end
end
