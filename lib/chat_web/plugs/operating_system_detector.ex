defmodule ChatWeb.Plugs.OperatingSystemDetector do
  @moduledoc """
  Parses User-Agent header to detect client's operating system
  and saves it into the session for later use.
  """
  @behaviour Plug

  alias Plug.Conn

  @spec init(Keyword.t()) :: Keyword.t()
  def init(_opts), do: []

  @spec call(Conn.t(), Keyword.t()) :: Conn.t()
  def call(%Conn{} = conn, _opts) do
    Conn.put_session(conn, :operating_system, detect_operating_system(conn))
  end

  defp detect_operating_system(%Conn{} = conn) do
    result =
      conn
      |> Conn.get_req_header("user-agent")
      |> List.first()
      |> UAParser.parse()

    result.os.family
  end
end
