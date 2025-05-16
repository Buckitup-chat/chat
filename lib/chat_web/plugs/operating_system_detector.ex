defmodule ChatWeb.Plugs.OperatingSystemDetector do
  @moduledoc """
  Parses User-Agent header to detect client's operating system and browser
  and saves it into the session for later use.
  """
  @behaviour Plug

  alias Plug.Conn

  @spec init(Keyword.t()) :: Keyword.t()
  def init(_opts), do: []

  @spec call(Conn.t(), Keyword.t()) :: Conn.t()
  def call(%Conn{} = conn, _opts) do
    user_agent_info = detect_user_agent_info(conn)

    conn
    |> Conn.put_session(:operating_system, user_agent_info.os)
    |> Conn.put_session(:browser, user_agent_info.browser)
    |> Conn.put_session(:is_safari, user_agent_info.is_safari)
  end

  defp detect_user_agent_info(%Conn{} = conn) do
    user_agent =
      conn
      |> Conn.get_req_header("user-agent")
      |> List.first()

    result = UAParser.parse(user_agent)

    # Check if Safari or Safari-based browser
    browser_family = result.family
    is_safari = safari?(browser_family, user_agent)

    %{
      os: result.os.family,
      browser: browser_family,
      is_safari: is_safari
    }
  end

  # Detect Safari and Safari-based browsers
  defp safari?(browser_family, user_agent) do
    case {browser_family, user_agent} do
      {"Safari", _} ->
        true

      {"Mobile Safari", _} ->
        true

      {_, user_agent} when is_binary(user_agent) ->
        safari_on_ios?(user_agent) || safari_on_mac?(user_agent)

      _ ->
        false
    end
  end

  defp safari_on_ios?(user_agent) do
    String.contains?(user_agent, "AppleWebKit") && String.contains?(user_agent, "Version") &&
      (String.contains?(user_agent, "iPhone") || String.contains?(user_agent, "iPad"))
  end

  defp safari_on_mac?(user_agent) do
    String.contains?(user_agent, "AppleWebKit") && String.contains?(user_agent, "Version") &&
      String.contains?(user_agent, "Safari") && !String.contains?(user_agent, "Chrome")
  end
end
