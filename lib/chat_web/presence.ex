defmodule ChatWeb.Presence do
  @moduledoc false

  use Phoenix.Presence,
    otp_app: :chat,
    pubsub_server: Chat.PubSub
end
