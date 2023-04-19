defmodule ChatWeb.Hooks.LiveModalHook do
  @moduledoc "LiveModal hook"

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias ChatWeb.LiveHelpers.LiveModal
  alias Phoenix.LiveView.{Session, Socket}

  @type name :: atom()
  @type params :: map()
  @type session :: %Session{}
  @type socket :: Socket.t()

  @spec on_mount(name(), params(), session(), socket()) :: {:cont, socket()}
  def on_mount(:default, _params, _session, %Socket{} = socket) do
    socket =
      socket
      |> attach_hook(:modal_hook, :handle_event, fn
        "modal:close", _params, socket -> {:halt, LiveModal.close_modal(socket)}
        _event, _params, socket -> {:cont, socket}
      end)
      |> assign(:live_modal, nil)

    {:cont, socket}
  end
end
