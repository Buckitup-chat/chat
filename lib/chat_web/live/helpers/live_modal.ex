defmodule ChatWeb.LiveHelpers.LiveModal do
  @moduledoc """
  Adds modal support for live pages.
  """
  import Phoenix.Component, only: [assign: 3]
  alias Phoenix.LiveView
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Socket

  defstruct [:component, :params]

  @type t() :: %__MODULE__{
          component: module(),
          params: %{String.t() => String.t()}
        }

  @type js_t() :: %JS{ops: list()}

  @spec open_modal(Socket.t(), module(), map()) :: Socket.t()
  def open_modal(%Socket{} = socket, module, params \\ %{}) when is_atom(module) do
    socket
    |> assign(:live_modal, %__MODULE__{component: module, params: params})
    |> send_js(opening_transition())
  end

  @spec close_modal(Socket.t()) :: Socket.t()
  def close_modal(%Socket{} = socket) do
    socket
    |> assign(:live_modal, nil)
    |> send_js(closing_transition())
  end

  @spec send_js(Socket.t(), js_t()) :: Socket.t()
  def send_js(%Socket{} = socket, %JS{ops: ops}) do
    LiveView.push_event(socket, "js-event", %{data: Jason.encode!(ops)})
  end

  defp opening_transition do
    %JS{}
    |> JS.show(to: "#modal")
    |> JS.show(to: "#modal-content")
  end

  defp closing_transition do
    %JS{}
    |> JS.hide(to: "#modal", transition: "fade-out", time: 0)
    |> JS.show(to: "#modal-content", transition: "fade-out-scale")
  end
end
