defmodule ChatWeb.Plugs.HexToBase64 do
  @moduledoc "Converts PostgreSQL hex-encoded bytea values in shape responses to unpadded base64."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    register_before_send(conn, &maybe_convert/1)
  end

  # In JSON wire format, Postgres hex bytea `\x1234` is encoded as `\\x1234`.
  # Quick scan avoids full JSON decode/walk/encode when no bytea values are present.
  @hex_marker "\\\\x"

  defp maybe_convert(%{status: status} = conn) when status in 200..299 do
    with [ct] <- get_resp_header(conn, "content-type"),
         true <- String.contains?(ct, "json"),
         body <- IO.iodata_to_binary(conn.resp_body),
         true <- String.contains?(body, @hex_marker) do
      body
      |> Jason.decode!()
      |> walk()
      |> Jason.encode!()
      |> then(&%{conn | resp_body: &1})
    else
      _ -> conn
    end
  end

  defp maybe_convert(conn), do: conn

  defp walk(list) when is_list(list), do: Enum.map(list, &walk/1)
  defp walk(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, walk(v)} end)
  defp walk(str) when is_binary(str), do: convert(str)
  defp walk(other), do: other

  defp convert("\\x" <> hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bin} -> Base.encode64(bin, padding: false)
      :error -> "\\x" <> hex
    end
  end

  defp convert("{" <> _ = str), do: maybe_convert_array(str)
  defp convert(str), do: str

  # Postgres array literal of hex bytea values → JSON array of base64 strings
  defp maybe_convert_array(str) do
    elements = PgInterop.Array.parse(str)

    if elements != [] and Enum.all?(elements, &hex_element?/1) do
      Enum.map(elements, &convert_element/1)
    else
      str
    end
  rescue
    _ -> str
  end

  defp hex_element?(nil), do: true

  defp hex_element?(str) when is_binary(str) do
    case str do
      "\\\\x" <> hex -> valid_hex?(hex)
      _ -> false
    end
  end

  defp hex_element?(_), do: false

  defp convert_element(nil), do: nil

  defp convert_element("\\\\x" <> hex) do
    {:ok, bin} = Base.decode16(hex, case: :mixed)
    Base.encode64(bin, padding: false)
  end

  defp valid_hex?(hex) when byte_size(hex) >= 2 do
    rem(byte_size(hex), 2) == 0 and hex =~ ~r/\A[0-9a-fA-F]+\z/
  end

  defp valid_hex?(_), do: false
end
