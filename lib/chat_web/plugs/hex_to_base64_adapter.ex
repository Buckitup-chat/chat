defmodule ChatWeb.Plugs.HexToBase64Adapter do
  @moduledoc "Wraps the conn adapter to convert PostgreSQL hex-encoded bytea values to unpadded base64 in chunked responses."

  @behaviour Plug.Conn.Adapter

  @hex_marker "\\\\x"

  def init(opts), do: opts

  def call(conn, _opts) do
    {adapter, payload} = conn.adapter
    %{conn | adapter: {__MODULE__, {adapter, payload}}}
  end

  @impl true
  def chunk({adapter, payload}, chunk_data) do
    case adapter.chunk(payload, convert_chunk(chunk_data)) do
      {:ok, body, new_payload} -> {:ok, body, {adapter, new_payload}}
      other -> other
    end
  end

  @impl true
  def send_chunked({adapter, payload}, status, headers) do
    {:ok, body, new_payload} = adapter.send_chunked(payload, status, headers)
    {:ok, body, {adapter, new_payload}}
  end

  @impl true
  def send_resp({adapter, payload}, status, headers, body) do
    {:ok, sent, new_payload} = adapter.send_resp(payload, status, headers, body)
    {:ok, sent, {adapter, new_payload}}
  end

  @impl true
  def send_file({adapter, payload}, status, headers, path, offset, length) do
    {:ok, sent, new_payload} = adapter.send_file(payload, status, headers, path, offset, length)
    {:ok, sent, {adapter, new_payload}}
  end

  @impl true
  def get_peer_data({adapter, payload}), do: adapter.get_peer_data(payload)

  @impl true
  def get_http_protocol({adapter, payload}), do: adapter.get_http_protocol(payload)

  @impl true
  def inform({adapter, payload}, status, headers), do: adapter.inform(payload, status, headers)

  @impl true
  def push({adapter, payload}, path, headers), do: adapter.push(payload, path, headers)

  @impl true
  def read_req_body({adapter, payload}, opts) do
    case adapter.read_req_body(payload, opts) do
      {:ok, data, new_payload} -> {:ok, data, {adapter, new_payload}}
      {:more, data, new_payload} -> {:more, data, {adapter, new_payload}}
      {:error, _} = err -> err
    end
  end

  @impl true
  def upgrade({adapter, payload}, protocol, opts), do: adapter.upgrade(payload, protocol, opts)

  defp convert_chunk(data) when is_binary(data) or is_list(data) do
    binary = IO.iodata_to_binary(data)

    if String.contains?(binary, @hex_marker) do
      binary
      |> Jason.decode!()
      |> walk()
      |> Jason.encode!()
    else
      data
    end
  rescue
    _ -> data
  end

  defp convert_chunk(data), do: data

  # --- JSON tree walk ---

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
