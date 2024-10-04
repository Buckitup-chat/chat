defmodule ChatWeb.MainLive.Layout.SearchBox do
  @moduledoc "Search bar component"
  use ChatWeb, :component
  import ChatWeb.LiveHelpers, only: [icon: 1]

  attr :type, :atom, required: true, doc: ":dialog or :room"

  def render(assigns) do
    ~H"""
    <.form
      :let={f}
      for={%{}}
      as={@type}
      id="search-box"
      class="w-full px-6 mt-3 flex items-center"
      phx-change="lobby/search"
      onkeydown="if (event.key == 'Enter') { event.preventDefault() }"
    >
      <div class="relative w-full">
        <div class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none">
          <.icon id="search" class="w-5 h-5 fill-gray-500 " />
        </div>
        <%= text_input(f, :name,
          placeholder: "Search",
          class:
            "bg-gray-300 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full pl-10 p-2.5"
        ) %>
        <button type="reset" name="reset" class="absolute inset-y-0 right-0 flex items-center pr-3">
          <.icon id="close" class="w-4 h-4 fill-gray-500 " />
        </button>
      </div>
    </.form>
    """
  end
end
