defmodule Tools.SocketPrivate do
  @moduledoc """
  Socket private storage helpers
  """
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket

  @key_prefix ChatWeb

  def get_private(%Socket{} = socket, key, default \\ nil) do
    socket.private |> Map.get({@key_prefix, key}, default)
  end

  def set_private(%Socket{} = socket, key, value) do
    socket
    |> LiveView.put_private({@key_prefix, key}, value)
  end

  def update_private(%Socket{} = socket, key, fun, default) do
    old_value = get_private(socket, key, default)

    socket
    |> set_private(key, fun.(old_value))
  end
end
