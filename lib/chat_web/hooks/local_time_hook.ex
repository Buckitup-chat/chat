defmodule ChatWeb.Hooks.LocalTimeHook do
  @moduledoc "Client local time handling"
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4]

  require Logger

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> attach_hook(:local_time, :handle_event, fn
       "local-time", params, socket -> {:halt, assign_time(socket, params)}
       _event, _params, socket -> {:cont, socket}
     end)}
  end

  def assign_time(
        socket,
        %{
          "locale" => locale,
          "timezone" => timezone,
          "timezone_offset" => timezone_offset,
          "timestamp" => timestamp
        }
      ) do
    timestamp
    |> DateTime.from_unix!()
    |> Chat.Time.set_time()

    socket
    |> assign(
      locale: locale || "en",
      timezone: timezone || "UTC",
      timezone_offset: timezone_offset || 0,
      monotonic_offset: timestamp |> Chat.Time.monotonic_offset()
    )
  end

  def assign_time(socket, _), do: socket
end
