defmodule ChatWeb.Hooks.LocalTimeHook do
  @moduledoc "Client local time handling"
  import Phoenix.LiveView

  require Logger

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> attach_hook(:local_time, :handle_event, fn
       "local-time",
       %{
         "locale" => locale,
         "timezone" => timezone,
         "timezone_offset" => timezone_offset,
         "timestamp" => timestamp
       },
       socket ->
         timestamp
         |> DateTime.from_unix!()
         |> Chat.Time.set_time()

         socket =
           socket
           |> assign(
             locale: locale || "en",
             timezone: timezone || "UTC",
             timezone_offset: timezone_offset || 0
           )

         {:halt, detach_hook(socket, :local_time, :handle_event)}

       _event, _params, socket ->
         {:cont, socket}
     end)}
  end
end
