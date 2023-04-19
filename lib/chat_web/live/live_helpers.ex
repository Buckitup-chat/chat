defmodule ChatWeb.LiveHelpers do
  @moduledoc false
  import Phoenix.Component

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
    assigns = assign_new(assigns, :hide_event, fn -> assigns[:hide_event] end)

    ~H"""
    <div
      id={@id}
      class="phx-modal fade-in"
      phx-remove={hide_modal(@id, @hide_event)}
      style="display: none;"
    >
      <div
        id={@id <> "-content"}
        class={"phx-modal-content border-0 rounded-lg bg-white p-4 fade-in-scale flex flex-col #{@class} t-modal"}
        phx-click-away={JS.dispatch("click", to: "#" <> @id <> "-close")}
        phx-window-keydown={JS.dispatch("click", to: "#" <> @id <> "-close")}
        phx-key="escape"
        style="display: none;"
      >
        <a
          id={@id <> "-close"}
          href="#"
          class="phx-modal-close w-full flex flex-row justify-end"
          phx-click={hide_modal(@id, @hide_event)}
        >
          <.icon id="close" class="w-4 h-4 flex fill-grayscale t-close-popup" />
        </a>

        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  def show_modal(id), do: show_modal(%JS{}, id)

  def show_modal(%JS{} = js, id) do
    js
    |> JS.show(to: "#" <> id)
    |> JS.show(to: "#" <> id <> "-content")
  end

  def hide_modal(id), do: hide_modal(id, nil, %JS{})

  def hide_modal(id, event, js \\ %JS{}) do
    js
    |> JS.hide(transition: "fade-out", to: "#" <> id)
    |> JS.hide(transition: "fade-out-scale", to: "#" <> id <> "-content")
    |> push(event)
  end

  defp push(%JS{} = js, nil), do: js
  defp push(%JS{} = js, event), do: JS.push(js, event)

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

  def dropdown(assigns) do
    ~H"""
    <div
      id={@id}
      class="dropdown t-dropdown"
      phx-click-away={JS.hide(transition: "fade-out", to: "#" <> @id)}
      phx-window-keydown={JS.hide(transition: "fade-out", to: "#" <> @id)}
      phx-key="escape"
      style="display: none;"
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  def open_dropdown(id), do: JS.show(transition: "fade-in", to: "#" <> id)

  def hide_dropdown(id), do: hide_dropdown(%JS{}, id)

  def hide_dropdown(%JS{} = js, id), do: js |> JS.hide(transition: "fade-out", to: "#" <> id)

  def stringify_commands(%JS{ops: ops}), do: Jason.encode!(ops)

  def icon(assigns) do
    ~H"""
    <svg class={@class}>
      <use href={"/images/icons/#{@id}.svg##{@id}"}></use>
    </svg>
    """
  end

  def open_content, do: %JS{} |> open_content()

  def open_content(%JS{} = js, time \\ 100) do
    js
    |> JS.hide(transition: "fade-out", to: "#navbarTop", time: 0)
    |> JS.hide(transition: "fade-out", to: "#navbarBottom", time: 0)
    |> JS.remove_class("hidden sm:flex",
      transition: "fade-in",
      to: "#contentContainer",
      time: time
    )
    |> JS.add_class("hidden", to: "#chatRoomBar", transition: "fade-out", time: 0)
  end

  def close_content(%JS{} = js, time \\ 100) do
    js
    |> JS.show(transition: "fade-in", to: "#navbarTop", display: "flex", time: time)
    |> JS.show(transition: "fade-in", to: "#navbarBottom", display: "flex", time: time)
    |> JS.add_class("hidden sm:flex", transition: "fade-out", to: "#contentContainer", time: 0)
    |> JS.remove_class("hidden", to: "#chatRoomBar", transition: "fade-in", time: time)
  end
end
