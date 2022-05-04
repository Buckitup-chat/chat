defmodule ChatWeb.LiveHelpers do
  @moduledoc false
  import Phoenix.LiveView
  import Phoenix.LiveView.Helpers

  alias Phoenix.LiveView.JS

  @doc """
  Renders a live component inside a modal.

  The rendered modal receives a `:return_to` option to properly update
  the URL when the modal is closed.

  ## Examples

      <.modal return_to={Routes.main_index_path(@socket, :index)}>
        <.live_component
          module={ChatWeb.MainLive.FormComponent}
          id={@main.id || :new}
          title={@page_title}
          action={@live_action}
          return_to={Routes.main_index_path(@socket, :index)}
          main: @main
        />
      </.modal>
  """
  def modal(assigns) do
    assigns = assign_new(assigns, :return_to, fn -> nil end)

    ~H"""
    <div id={@id} class="hidden phx-modal fade-in" phx-remove={hide_modal(@id)}>
      <div
        id={@id <> "-content"}
        class={"phx-modal-content border-0 rounded-lg bg-white p-4 fade-in-scale flex flex-col #{@class}"}
        phx-click-away={JS.dispatch("click", to: "#close")}
        phx-window-keydown={JS.dispatch("click", to: "#close")}
        phx-key="escape"
      >   
        <a id="close" href="#" class="phx-modal-close w-full flex flex-row justify-end" phx-click={hide_modal(@id)}>
          <svg class="w-4 h-4 flex fill-grayscale">
            <use href="/images/icons.svg#close"></use>
          </svg>
        </a>
        
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  defp hide_modal(id, js \\ %JS{}) do
    js
    |> JS.add_class("hidden",  to: "#" <> id)
    |> JS.hide(to: "#" <> id, transition: "fade-out")
    |> JS.remove_attribute("style", to: "#" <> id)
  end

  def classes(%{} = optionals), do: classes([], optionals)
  def classes(constants), do: classes(constants, %{})

  def classes(nil, optionals), do: classes([], optionals)

  def classes("" <> constant, optionals) do
    classes([constant], optionals)
  end

  def classes(constants, optionals) do
    [
      constants,
      optionals
      |> Enum.filter(&elem(&1, 1))
      |> Enum.map(&elem(&1, 0))
    ]
    |> Enum.concat()
    |> Enum.join(" ")
  end
end
