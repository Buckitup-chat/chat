defmodule ChatWeb.MainLive.Page.Shared do
  @moduledoc "Shared page functions"

  alias Phoenix.HTML.Safe

  def mime_type(nil), do: "application/octet-stream"
  def mime_type(""), do: mime_type(nil)
  def mime_type(x), do: x

  def format_size(n) when n > 1_000_000_000, do: "#{trunc(n / 100_000_000) / 10} Gb"
  def format_size(n) when n > 1_000_000, do: "#{trunc(n / 100_000) / 10} Mb"
  def format_size(n) when n > 1_000, do: "#{trunc(n / 100) / 10} Kb"
  def format_size(n), do: "#{n} b"

  def is_memo?(text), do: String.length(text) > 150

  def render_to_html_string(assigns, render_fun) do
    IO.inspect assigns
    IO.inspect render_fun
    assigns
    |> then(render_fun)
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
