defmodule ChatWeb.CoreComponents do
  @moduledoc "Basic components"
  #  use Phoenix.Component
  #
  #  alias Phoenix.LiveView.JS
  #
  #  @doc """
  #  Renders a button.
  #
  #  ## Examples
  #
  #      <.button>Send!</.button>
  #      <.button phx-click="go" class="ml-2">Send!</.button>
  #  """
  #  attr :type, :string, default: nil
  #  attr :class, :string, default: nil
  #  attr :rest, :global, include: ~w(disabled form name value)
  #
  #  slot :inner_block, required: true
  #
  #  def button(assigns) do
  #    ~H"""
  #    <button
  #      type={@type}
  #      class={[
  #        "phx-submit-loading:opacity-75 rounded-lg bg-black border-0 justify-center",
  #        "text-white h-11 px-10 mt-2",
  #        @class
  #      ]}
  #      {@rest}
  #    >
  #      <%= render_slot(@inner_block) %>
  #    </button>
  #    """
  #  end
end
