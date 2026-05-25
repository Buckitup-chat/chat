defmodule Chat.TimeKeeper.Source do
  @moduledoc false

  @ntp_timeout 3_000
  @ntp_servers ["pool.ntp.org", "time.google.com", "time.cloudflare.com"]
  @ntp_epoch_offset 2_208_988_800

  @doc "Try to get time from NTP servers. Returns `{:ok, unix}` or `:error`."
  def try_ntp(timeout \\ @ntp_timeout) do
    Enum.find_value(@ntp_servers, :error, fn server ->
      case ntp_query(server, timeout) do
        {:ok, unix} -> {:ok, unix}
        :error -> nil
      end
    end)
  end

  @doc "Read persisted unix timestamp from file."
  def read_persisted_time(path) do
    with {:ok, content} <- File.read(path),
         {unix, _} <- content |> String.trim() |> Integer.parse() do
      DateTime.from_unix!(unix)
    else
      _ -> nil
    end
  end

  def persist_path do
    Application.get_env(:chat, :timekeeper_path, "priv/timekeeper_time")
  end

  # --- NTP ---

  defp ntp_query(server, timeout) do
    with {:ok, addr} <- resolve_host(server, timeout),
         {:ok, socket} <- :gen_udp.open(0, [:binary, active: false]),
         :ok <- :gen_udp.send(socket, addr, 123, ntp_request_packet()),
         {:ok, {_, _, response}} <- :gen_udp.recv(socket, 0, timeout) do
      :gen_udp.close(socket)
      parse_ntp_response(response)
    else
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp resolve_host(server, timeout) do
    case :inet.getaddr(~c"#{server}", :inet, timeout) do
      {:ok, addr} -> {:ok, addr}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp ntp_request_packet do
    <<0x1B>> <> :binary.copy(<<0>>, 47)
  end

  defp parse_ntp_response(<<_::binary-size(40), seconds::32, _fraction::32, _::binary>>)
       when seconds > @ntp_epoch_offset do
    {:ok, seconds - @ntp_epoch_offset}
  end

  defp parse_ntp_response(_), do: :error
end
