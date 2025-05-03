defmodule ChatWeb.ErrorHelpers do
  @moduledoc """
  Conveniences for translating and building error messages.
  """
  use PhoenixHTMLHelpers

  import Phoenix.HTML.Form

  @doc """
  Generates tag for inlined form input errors.
  """
  def error_tag(form, field) do
    Enum.map(Keyword.get_values(form.errors, field), fn error ->
      content_tag(:span, translate_error(error),
        class: "invalid-feedback",
        phx_feedback_for: input_name(form, field)
      )
    end)
  end

  @doc """
  Translates an error message.
  """
  def translate_error({msg, opts}) do
    # Because the error messages we show in our forms and APIs
    # are defined inside Ecto, we handle them directly.
    # Note: previously this used gettext which has been removed
    if count = opts[:count] do
      String.replace(msg, "%{count}", to_string(count))
    else
      msg
    end
  end
end
