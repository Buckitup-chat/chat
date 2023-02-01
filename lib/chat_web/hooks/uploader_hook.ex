defmodule ChatWeb.Hooks.UploaderHook do
  @moduledoc """
  LiveView hook that adds file upload and handles uploader events.
  """

  import Phoenix.LiveView

  alias ChatWeb.LiveHelpers.Uploader
  alias Phoenix.LiveView.{Session, Socket}

  @type name :: atom()
  @type params :: map()
  @type session :: %Session{}
  @type socket :: Socket.t()

  @spec on_mount(name(), params(), session(), socket()) :: {:cont, socket()}
  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> Uploader.allow_file_upload()
     |> attach_hook(:uploader, :handle_event, fn
       "upload:cancel", params, socket ->
         {:halt, Uploader.cancel_upload(socket, params)}

       "upload:pause", params, socket ->
         {:halt, Uploader.pause_upload(socket, params)}

       "upload:resume", params, socket ->
         {:halt, Uploader.resume_upload(socket, params)}

       _event, _params, socket ->
         {:cont, socket}
     end)}
  end
end
