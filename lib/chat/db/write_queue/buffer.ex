defmodule Chat.Db.WriteQueue.Buffer do
  @moduledoc """
  Record for write queue manipulations
  """
  import Chat.Db.WriteQueue.ReadStream

  require Logger
  require Record

  Record.defrecord(:buffer,
    data: nil,
    delete_keys: nil,
    log: nil,
    stream: nil,
    chunk: nil
  )

  def buffer_has_chunk?(buffer(chunk: chunk)), do: nil != chunk
  def buffer_has_stream?(buffer(stream: stream)), do: nil != stream

  def buffer_chunk(buf, chunk), do: buffer(buf, chunk: chunk)
  def buffer_stream(buf, stream), do: buffer(buf, stream: stream)

  def buffer_add_data(buffer(data: list) = buf, data), do: buffer(buf, data: append(list, data))
  def buffer_add_log(buffer(log: list) = buf, data), do: buffer(buf, log: append(list, data))

  def buffer_add_deleted(buffer(delete_keys: list) = buf, key),
    do: buffer(buf, delete_keys: append(list, key))

  def buffer_yield(buf) do
    cond do
      data = buffer(buf, :data) ->
        "data" |> log()
        {{:write, data}, buffer(buf, data: nil)}

      keys = buffer(buf, :delete_keys) ->
        [k | _] = keys
        "delete #{inspect(k)} ..." |> log()
        {{:delete, keys}, buffer(buf, delete_keys: nil)}

      logs = buffer(buf, :log) ->
        [{k, _} | _] = logs
        "log #{inspect(k)} ..." |> log()
        {{:write, logs}, buffer(buf, log: nil)}

      stream = buffer(buf, :stream) ->
        "stream" |> log()
        handle_stream(buf, stream)

      chunk = buffer(buf, :chunk) ->
        "chunk" |> log()
        {{:write, [chunk]}, buffer(buf, chunk: nil)}

      true ->
        {:ignored, buf}
    end
  end

  defp handle_stream(buf, stream) do
    {data, stream} = stream_yield(stream)

    {{:write, data}, buffer(buf, stream: stream)}
  end

  defp stream_yield(stream) do
    {data, updated_stream} = read_stream_yield(stream)

    if read_stream_empty?(updated_stream) do
      {data, nil}
    else
      {data, updated_stream}
    end
  end

  defp log(message), do: Logger.info("[queue] #{message}")

  defp append(nil, value), do: [value]
  defp append(list, value), do: [value | list]
end
