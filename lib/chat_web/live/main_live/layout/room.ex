defmodule ChatWeb.MainLive.Layout.Room do
  use ChatWeb, :component

  alias Phoenix.LiveView.JS

  attr :checked, :boolean, default: false
  attr :class, :string, default: nil
  attr :description, :string, required: true
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, required: true

  def type_option(assigns) do
    ~H"""
    <a class={"inline" <> if(@class, do: " #{@class}", else: "")}>
      <input
        checked={@checked}
        class="cursor-pointer text-orange-500"
        id={@id}
        name="new_room[type]"
        phx-click={switch_type(@id, @description)}
        type="radio"
        value={@value}
      />

      <label class="cursor-pointer ml-1 text-black/50 text-sm" for={@id}>
        <%= @name %>
      </label>
    </a>
    """
  end

  defp switch_type(id, description) do
    JS.dispatch("room:switch-type",
      to: "##{id}",
      detail: %{
        description: description,
        id: "roomTypeDescription"
      }
    )
  end
end
