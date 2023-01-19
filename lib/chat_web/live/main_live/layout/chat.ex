defmodule ChatWeb.MainLive.Layout.Chat do
  @moduledoc """
  Chat components
  """
  use ChatWeb, :component

  def loader(assigns) do
    ~H"""
    <div class="flex flex-row justify-end transition-all hidden" id="chat-loader">
      <div class="m-1 sm:mx-8 bg-purple50 rounded-lg shadow-lg inline-flex items-center px-4 py-2 font-semibold leading-6 text-sm text-black/50 shadow transition ease-in-out duration-150">
        <svg
          class="animate-spin -ml-1 mr-3 h-5 w-5 text-white"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
        >
          <circle class="opacity-50" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
          </circle>
          <path
            class="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
          >
          </path>
        </svg>
        Loading...
      </div>
    </div>
    """
  end
end
