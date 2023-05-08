defmodule ChatWeb.LiveHelpers.LiveModal do
  @moduledoc """
  Adds modal support for live pages.
  """
  import ChatWeb.LiveHelpers.Shared, only: [send_js: 2]
  import Phoenix.Component, only: [assign: 3]
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Socket

  defstruct [:component, :params]

  @type t() :: %__MODULE__{
          component: module(),
          params: %{String.t() => String.t()}
        }

  @spec open_modal(Socket.t(), module(), map()) :: Socket.t()
  def open_modal(%Socket{} = socket, module, params \\ %{}) when is_atom(module) do
    socket
    |> assign(:live_modal, %__MODULE__{component: module, params: params})
    |> send_js(opening_transition())
  end

  @spec close_modal(Socket.t()) :: Socket.t()
  def close_modal(%Socket{} = socket) do
    Process.send_after(self(), :close_modal, 200)

    socket
    |> send_js(closing_transition())
  end

  defp opening_transition do
    %JS{}
    |> JS.show(to: "#modal")
    |> JS.show(to: "#modal-content")
  end

  defp closing_transition do
    %JS{}
    |> JS.hide(transition: "fade-out", to: "#modal")
    |> JS.hide(transition: "fade-out-scale", to: "#modal-content")
  end
end
