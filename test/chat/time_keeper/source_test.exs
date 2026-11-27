defmodule Chat.TimeKeeper.SourceTest do
  use ExUnit.Case, async: true

  import Support.Rewire

  alias Chat.TimeKeeper.Source

  @ntp_epoch_offset 2_208_988_800
  @unix 1_800_000_000

  defmodule InetOk do
    def getaddr(_host, _family, _timeout), do: {:ok, {127, 0, 0, 1}}
  end

  defmodule InetError do
    def getaddr(_host, _family, _timeout), do: {:error, :nxdomain}
  end

  defmodule InetRaise do
    def getaddr(_host, _family, _timeout), do: raise(ArgumentError, "bad host")
  end

  defmodule InetOnlyCloudflare do
    def getaddr(~c"time.cloudflare.com", _family, _timeout), do: {:ok, {127, 0, 0, 1}}
    def getaddr(_host, _family, _timeout), do: {:error, :nxdomain}
  end

  defmodule UdpReply do
    def open(_port, _opts), do: {:ok, :socket}
    def send(:socket, _addr, 123, <<0x1B, _::binary-size(47)>>), do: :ok
    def recv(:socket, 0, _timeout), do: {:ok, {{127, 0, 0, 1}, 123, Process.get(:ntp_response)}}
    def close(:socket), do: :ok
  end

  defmodule UdpTimeout do
    def open(_port, _opts), do: {:ok, :socket}
    def send(_socket, _addr, _port, _packet), do: :ok
    def recv(_socket, _length, _timeout), do: {:error, :timeout}
    def close(_socket), do: :ok
  end

  defmodule UdpExit do
    def open(_port, _opts), do: exit(:port_closed)
    def send(_socket, _addr, _port, _packet), do: :ok
    def recv(_socket, _length, _timeout), do: {:error, :closed}
    def close(_socket), do: :ok
  end

  describe "try_ntp/1" do
    test "returns unix time from a valid NTP reply" do
      put_ntp_response(@unix + @ntp_epoch_offset)

      assert {:ok, @unix} = rewire(Source, inet: InetOk, gen_udp: UdpReply).try_ntp(10)
    end

    test "falls through servers until one answers" do
      put_ntp_response(@unix + @ntp_epoch_offset)

      assert {:ok, @unix} =
               rewire(Source, inet: InetOnlyCloudflare, gen_udp: UdpReply).try_ntp(10)
    end

    test "fails when hosts don't resolve" do
      assert :error = rewire(Source, inet: InetError, gen_udp: UdpReply).try_ntp(10)
    end

    test "fails when resolving raises" do
      assert :error = rewire(Source, inet: InetRaise, gen_udp: UdpReply).try_ntp(10)
    end

    test "fails when the reply times out" do
      assert :error = rewire(Source, inet: InetOk, gen_udp: UdpTimeout).try_ntp(10)
    end

    test "fails when the socket exits" do
      assert :error = rewire(Source, inet: InetOk, gen_udp: UdpExit).try_ntp(10)
    end

    test "rejects a truncated reply" do
      Process.put(:ntp_response, <<0::size(40 * 8)>>)

      assert :error = rewire(Source, inet: InetOk, gen_udp: UdpReply).try_ntp(10)
    end

    test "rejects a reply before the unix epoch" do
      put_ntp_response(@ntp_epoch_offset)

      assert :error = rewire(Source, inet: InetOk, gen_udp: UdpReply).try_ntp(10)
    end
  end

  describe "read_persisted_time/1" do
    @describetag :tmp_dir

    test "reads a trimmed unix timestamp", %{tmp_dir: dir} do
      path = Path.join(dir, "time")
      File.write!(path, " #{@unix}\n")

      assert DateTime.from_unix!(@unix) == Source.read_persisted_time(path)
    end

    test "returns nil for a missing file", %{tmp_dir: dir} do
      assert nil == dir |> Path.join("missing") |> Source.read_persisted_time()
    end

    test "returns nil for garbage content", %{tmp_dir: dir} do
      path = Path.join(dir, "time")
      File.write!(path, "not a time")

      assert nil == Source.read_persisted_time(path)
    end
  end

  test "persist_path/0 defaults to the priv file" do
    assert "priv/timekeeper_time" == Source.persist_path()
  end

  defp put_ntp_response(seconds) do
    Process.put(:ntp_response, <<0::size(40 * 8), seconds::32, 0::32>>)
  end
end
