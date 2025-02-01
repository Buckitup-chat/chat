defmodule ChatWeb.LiveHelpers.SocketPrivate do
  @moduledoc """
  Socket private storage helpers
  """

  # alias Phoenix.LiveView
  # alias Phoenix.LiveView.Socket
  #
  # @key_prefix ChatWeb

  @deprecated "use Tools.SocketPrivate instead"
  defdelegate get_private(socket, key, default \\ nil), to: Tools.SocketPrivate
  # def get_private(%Socket{} = socket, key, default \\ nil) do
  #   socket.private |> Map.get({@key_prefix, key}, default)
  # end

  @deprecated "use Tools.SocketPrivate instead"
  defdelegate set_private(socket, key, value), to: Tools.SocketPrivate
  # def set_private(%Socket{} = socket, key, value) do
  #   socket
  #   |> LiveView.put_private({@key_prefix, key}, value)
  # end
end
