defmodule ChatWeb.Hooks.OnlinersSyncHook do
  @moduledoc """
  Handles onliners sync messages sent from the platform via PubSub.
  """

  import Phoenix.LiveView

  alias ChatWeb.Helpers.OnlinersSync
  alias Phoenix.LiveView.{Session, Socket}
  alias Phoenix.PubSub

  @type name :: atom()
  @type params :: map()
  @type session :: %Session{}
  @type socket :: Socket.t()

  @incoming_topic "platform_onliners->chat_onliners"

  @spec on_mount(name(), params(), session(), socket()) :: {:cont, socket()}
  def on_mount(:default, _params, _session, socket) do
    PubSub.subscribe(Chat.PubSub, @incoming_topic)

    {:cont,
     socket
     |> attach_hook(:onliners_sync, :handle_info, fn
       "get_user_keys", socket ->
         {:halt, OnlinersSync.get_user_keys(socket)}

       _message, socket ->
         {:cont, socket}
     end)}
  end
end
