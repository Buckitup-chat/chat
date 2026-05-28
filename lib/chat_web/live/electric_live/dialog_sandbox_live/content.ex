defmodule ChatWeb.ElectricLive.DialogSandboxLive.Content do
  @moduledoc false

  @known_types ~w(inline_file inline_image file image video)

  def parse(plaintext) do
    case Jason.decode(plaintext) do
      {:ok, decoded} -> classify(decoded)
      {:error, _} -> {:text, plaintext}
    end
  end

  defp classify(value) do
    cond do
      is_binary(value) ->
        {:text, value}

      is_list(value) ->
        {:composed, Enum.map(value, &classify/1)}

      is_map(value) ->
        case Map.keys(value) do
          [key] when key in @known_types -> parse_typed(key, value[key])
          _ -> {:unknown, Jason.encode!(value)}
        end

      true ->
        {:text, inspect(value)}
    end
  end

  defp parse_typed("inline_file", [name, size, mime, ts, data_b64]) do
    {:inline_file, %{name: name, size: size, mime: mime, timestamp: ts, data_b64: data_b64}}
  end

  defp parse_typed("inline_image", [w, h, thumbhash, name, size, mime, ts, data_b64]) do
    {:inline_image,
     %{
       w_aspect: w,
       h_aspect: h,
       thumbhash_b64: thumbhash,
       name: name,
       size: size,
       mime: mime,
       timestamp: ts,
       data_b64: data_b64
     }}
  end

  defp parse_typed("file", [name, size, mime, ts, file_id, enc_secret]) do
    {:file,
     %{
       name: name,
       size: size,
       mime: mime,
       timestamp: ts,
       file_id: file_id,
       enc_secret_b64: enc_secret
     }}
  end

  defp parse_typed("image", [w, h, thumbhash, name, size, mime, ts, file_id, enc_secret]) do
    {:image,
     %{
       w_aspect: w,
       h_aspect: h,
       thumbhash_b64: thumbhash,
       name: name,
       size: size,
       mime: mime,
       timestamp: ts,
       file_id: file_id,
       enc_secret_b64: enc_secret
     }}
  end

  defp parse_typed("video", [w, h, thumbhash, name, size, mime, ts, file_id, enc_secret]) do
    {:video,
     %{
       w_aspect: w,
       h_aspect: h,
       thumbhash_b64: thumbhash,
       name: name,
       size: size,
       mime: mime,
       timestamp: ts,
       file_id: file_id,
       enc_secret_b64: enc_secret
     }}
  end

  defp parse_typed(key, value), do: {:unknown, Jason.encode!(%{key => value})}

  def prepare_for_send(text_input) do
    case Jason.decode(text_input) do
      {:ok, _} -> text_input
      {:error, _} -> Jason.encode!(text_input)
    end
  end

  def to_json({:text, string}), do: Jason.encode!(string)

  def to_json({:inline_file, m}) do
    Jason.encode!(%{"inline_file" => [m.name, m.size, m.mime, m.timestamp, m.data_b64]})
  end

  def to_json({:inline_image, m}) do
    Jason.encode!(%{
      "inline_image" => [
        m.w_aspect,
        m.h_aspect,
        m.thumbhash_b64,
        m.name,
        m.size,
        m.mime,
        m.timestamp,
        m.data_b64
      ]
    })
  end

  def to_json({:file, m}) do
    Jason.encode!(%{
      "file" => [m.name, m.size, m.mime, m.timestamp, m.file_id, m.enc_secret_b64]
    })
  end

  def to_json({:image, m}) do
    Jason.encode!(%{
      "image" => [
        m.w_aspect,
        m.h_aspect,
        m.thumbhash_b64,
        m.name,
        m.size,
        m.mime,
        m.timestamp,
        m.file_id,
        m.enc_secret_b64
      ]
    })
  end

  def to_json({:video, m}) do
    Jason.encode!(%{
      "video" => [
        m.w_aspect,
        m.h_aspect,
        m.thumbhash_b64,
        m.name,
        m.size,
        m.mime,
        m.timestamp,
        m.file_id,
        m.enc_secret_b64
      ]
    })
  end

  def to_json({:composed, elements}), do: Jason.encode!(Enum.map(elements, &to_raw/1))
  def to_json({:unknown, json}), do: json

  defp to_raw({:text, s}), do: s
  defp to_raw(parsed), do: parsed |> to_json() |> Jason.decode!()

  def format_size(bytes) when is_number(bytes) do
    cond do
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  def format_size(_), do: "? B"
end
