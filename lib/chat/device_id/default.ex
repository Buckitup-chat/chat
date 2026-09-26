defmodule Chat.DeviceId.Default do
  @moduledoc "Fallback chain: HTTPS domain → localhost MAC"

  @behaviour Chat.DeviceId

  @impl true
  def id do
    with :skip <- from_domain(),
         :skip <- from_mac() do
      "Unknown"
    end
  end

  defp from_domain do
    case Application.get_env(:chat, ChatWeb.Endpoint)[:url][:host] do
      host when is_binary(host) and host not in ["localhost", ""] ->
        "Server_#{host}"

      _ ->
        :skip
    end
  end

  defp from_mac do
    case first_hw_address() do
      nil -> :skip
      mac -> "Localhost_#{mac}"
    end
  end

  defp first_hw_address do
    with {:ok, ifaddrs} <- :inet.getifaddrs() do
      ifaddrs
      |> Enum.reject(&loopback?/1)
      |> Enum.find_value(&extract_mac/1)
    else
      _ -> nil
    end
  end

  defp loopback?({name, _}), do: name == ~c"lo"

  defp extract_mac({_name, opts}) do
    Enum.find_value(opts, fn
      {:hwaddr, [0, 0, 0, 0, 0, 0]} -> nil
      {:hwaddr, addr} when length(addr) == 6 -> format_mac(addr)
      _ -> nil
    end)
  end

  defp format_mac(bytes) do
    bytes |> :binary.list_to_bin() |> Base.encode16(case: :lower)
  end
end
