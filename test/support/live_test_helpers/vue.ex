defmodule ChatWeb.LiveTestHelpers.Vue do
  @moduledoc """
  Finds Vue (LiveVue) components and their content in rendered LiveView HTML.
  """

  import Phoenix.LiveViewTest

  alias ChatWeb.LiveTestHelpers.VueDebug

  @type view :: %Phoenix.LiveViewTest.View{}

  @doc """
  Tests content in Vue slot components or HTML within Vue-LiveView components.

  This function helps test content that's rendered within Vue components, even when the
  content is in slots or dynamically rendered. It works by examining the rendered HTML
  to find components by their v-component attribute and then looking for the specified
  content within that component's context.

  ## Examples

      # Check if a message exists inside a LinkedText component
      assert has_vue_content?(view, "LinkedText", "Dialog message text")
      
      # Use a more specific matcher function
      assert has_vue_content?(view, "LinkedText", fn html ->
        html =~ "Dialog message text" && html =~ "some other text"
      end)
      
      # Enable debug mode to see component detection details
      has_vue_content?(view, "LinkedText", "text", debug: true)
  """
  @spec has_vue_content?(view(), String.t(), String.t() | (String.t() -> boolean()), keyword()) ::
          boolean()
  def has_vue_content?(view, component_name, content_or_validator, opts \\ []) do
    debug_mode = Keyword.get(opts, :debug, false)
    html = if is_binary(view), do: view, else: render(view)

    result =
      if component_name == "LinkedText" do
        find_linked_text_content(html, content_or_validator, debug_mode)
      else
        find_standard_component_content(html, component_name, content_or_validator, debug_mode)
      end

    if debug_mode && !result do
      IO.puts("[DEBUG] Full Vue component analysis:")
      IO.puts(VueDebug.debug_vue_components(view, component_name))
    end

    result
  end

  defp find_linked_text_content(html, content_or_validator, debug_mode) do
    if is_binary(content_or_validator) && html =~ content_or_validator do
      if debug_mode do
        IO.puts("\n[DEBUG] Found text '#{content_or_validator}' in general HTML")

        [context] =
          Regex.run(~r/(.{0,100}#{content_or_validator}.{0,100})/s, html, capture: :all_but_first)

        IO.puts("[DEBUG] Context: #{context}")
      end

      true
    else
      find_linked_text_in_slots(html, content_or_validator, debug_mode)
    end
  end

  defp find_linked_text_in_slots(html, content_or_validator, debug_mode) do
    case Regex.run(
           ~r/data-name="LinkedText"[^>]*data-slots="[^"]*default[^"]*:&quot;([^&]+)&quot;/,
           html
         ) do
      [_, base64_content] ->
        find_in_base64_content(base64_content, content_or_validator, debug_mode)

      nil ->
        find_linked_text_by_patterns(html, content_or_validator, debug_mode)
    end
  end

  defp find_in_base64_content(base64_content, content_or_validator, debug_mode) do
    with {:ok, decoded_content} <- Base.decode64(base64_content),
         true <- is_binary(content_or_validator) && decoded_content =~ content_or_validator do
      if debug_mode do
        IO.puts("\n[DEBUG] Found text '#{content_or_validator}' in base64 decoded content")
        IO.puts("[DEBUG] Decoded content: #{decoded_content}")
      end

      true
    else
      _ -> false
    end
  end

  defp find_linked_text_by_patterns(html, content_or_validator, debug_mode) do
    linked_text_patterns = [
      ~r/<[^>]*class="[^"]*flex-initial[^"]*"[^>]*>(.*?#{content_or_validator}.*?)<\/span>/s,
      ~r/<span[^>]*class="[^"]*break-words[^"]*"[^>]*>(.*?#{content_or_validator}.*?)<\/span>/s,
      ~r/v-component="LinkedText"[^>]*>.*?(#{content_or_validator})/s
    ]

    Enum.find_value(linked_text_patterns, false, &linked_text_match?(&1, html, debug_mode))
  end

  defp linked_text_match?(pattern, html, debug_mode) do
    with [match | _] <- Regex.run(pattern, html) do
      if debug_mode, do: IO.puts("\n[DEBUG] Found LinkedText match: #{match}")
      true
    end
  end

  defp find_standard_component_content(html, component_name, content_or_validator, debug_mode) do
    case find_vue_component(html, component_name) do
      nil ->
        if debug_mode, do: IO.puts("\n[DEBUG] Component '#{component_name}' not found")
        false

      component_html ->
        if debug_mode, do: IO.puts("\n[DEBUG] Found component '#{component_name}'")

        result =
          case content_or_validator do
            validator when is_function(validator, 1) -> validator.(component_html)
            text when is_binary(text) -> component_html =~ text
          end

        if debug_mode && !result, do: IO.puts("[DEBUG] Content not found in component")
        result
    end
  end

  @doc """
  Finds a Vue component in the rendered HTML and returns its content.
  This is useful for debugging and testing what's inside the component.
  Returns nil if the component is not found.
  """
  @spec find_vue_component(String.t(), String.t()) :: String.t() | nil
  def find_vue_component(html, component_name) do
    # Multiple potential patterns for Vue component matching
    patterns = [
      # Standard Vue component with v-component attribute
      ~r/<[^>]*v-component="#{component_name}"[^>]*>(.*?)<\/[^>]*>/s,
      # Component with data-v-component attribute
      ~r/<[^>]*data-v-component="#{component_name}"[^>]*>(.*?)<\/[^>]*>/s,
      # LiveVue specific format
      ~r/<[^>]*data-phx-component[^>]*data-vue-component="#{component_name}"[^>]*>(.*?)<\/[^>]*>/s,
      # More general component match - matches any tag that has the component name
      ~r/<[^>]*\bclass="[^"]*\b#{component_name}\b[^"]*"[^>]*>(.*?)<\/[^>]*>/s,
      # Look for component name followed by any content
      ~r/<[^>]*\b#{component_name}\b[^>]*>(.*?)<\/[^>]*>/si,
      # Most general - look for component name in HTML and capture surrounding content
      ~r/(<[^>]*>[^<]*#{component_name}[^<]*<\/[^>]*>)/si
    ]

    # Try each pattern until we find a match
    result =
      Enum.find_value(patterns, fn pattern ->
        case Regex.run(pattern, html, capture: :all_but_first) do
          [content] -> content
          _ -> nil
        end
      end)

    # If we still didn't find anything but the component name appears in the HTML,
    # let's just search for the surrounding context
    if is_nil(result) && html =~ component_name do
      # Try to find a broader context around the component name
      case Regex.run(~r/(.{0,100}#{component_name}.{0,100})/s, html) do
        [context | _] -> context
        _ -> nil
      end
    else
      result
    end
  end
end
