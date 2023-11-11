defmodule Chat.Sync.Camera.Sensor do
  @moduledoc """
  Get image by url or ONVIF supported host

  Url with no path is considered to be ONVIF profile S compatible
  """
  @dialyzer {:no_match, [get_onvif_endpoint: 1]}

  alias Onvif.Media.Ver10.GetProfiles
  alias Onvif.Media.Ver10.GetSnapshotUri

  defstruct [:url, :auth, :error, :endpoint, :content, :media_type]

  def get_image(url) do
    %__MODULE__{url: url}
    |> parse_url()
    |> get_endpoint()
    |> get_content()
    |> case do
      %{error: nil, content: data, media_type: type} -> {:ok, {type, data}}
      %{error: err} -> {:error, err}
    end
  end

  defp parse_url(%__MODULE__{url: url} = context) do
    URI.parse(url)
    |> case do
      %{host: host} when host in [nil, ""] ->
        %{context | error: "URL invalid (no hostname)"}

      %{scheme: s} when s not in ["http", "https"] ->
        %{context | error: "URL invalid (no known scheme)"}

      %{userinfo: nil} = uri ->
        %{context | url: uri}

      %{userinfo: creds} = uri ->
        %{context | url: uri, auth: creds |> String.split(":")}
    end
  end

  defp get_endpoint(%__MODULE__{error: nil, url: %{path: path}} = context) do
    case path do
      nil -> get_onvif_endpoint(context)
      "/" -> get_onvif_endpoint(context)
      _ -> build_web_endpoint(context)
    end
  end

  defp get_endpoint(%__MODULE__{} = context), do: context

  defp build_web_endpoint(%{url: u} = context) do
    %{u | userinfo: nil}
    |> URI.to_string()
    |> then(&%{context | endpoint: &1})
  end

  defp get_onvif_endpoint(%{url: uri, auth: auth} = context) do
    with onvif_url <- URI.to_string(uri),
         auth_type <- (auth && :digest_auth) || :no_auth,
         [{:ok, %{reference_token: profile}} | _] <- GetProfiles.request(onvif_url, auth_type),
         {:ok, image_url} <- GetSnapshotUri.request(onvif_url, [profile]) do
      %{context | endpoint: image_url}
    else
      _ -> %{context | error: "Error getting ONVIF endpoint"}
    end
  end

  defp get_content(%__MODULE__{error: nil, auth: creds, endpoint: url} = context) do
    case creds do
      nil ->
        [{Tesla.Middleware.Timeout, timeout: 1000}]

      [login, password] ->
        [
          {Tesla.Middleware.Timeout, timeout: 1000},
          {Tesla.Middleware.DigestAuth, %{username: login, password: password}}
        ]
    end
    |> Tesla.client(Tesla.Adapter.Mint)
    |> Tesla.get(url)
    |> case do
      {:ok, %{status: 200, headers: headers, body: body}} ->
        %{context | content: body, media_type: find_content_type(headers)}

      {:ok, %{status: code}} ->
        %{context | error: "Error getting image [#{code}]"}

      {:error, _} ->
        %{context | error: "Error getting image"}
    end
  end

  defp get_content(%__MODULE__{} = context), do: context

  defp find_content_type(headers) do
    Enum.find_value(headers, fn {name, value} ->
      if name == "content-type" do
        value
      end
    end) || "application/octet-stream"
  end
end
