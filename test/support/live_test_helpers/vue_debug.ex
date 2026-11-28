defmodule ChatWeb.LiveTestHelpers.VueDebug do
  @moduledoc """
  Debug helpers to inspect Vue (LiveVue) components rendered in a LiveView.
  """

  import Phoenix.LiveViewTest

  @type view :: %Phoenix.LiveViewTest.View{}

  @doc """
  Debug helper to inspect Vue component rendering in a LiveView.
  This will print component details to help diagnose rendering issues.

  ## Examples

      # Print all Vue components in the view
      debug_vue_components(view)
      
      # Focus on a specific component
      debug_vue_components(view, "LinkedText")
  """
  @spec debug_vue_components(view(), String.t() | nil) :: String.t()
  def debug_vue_components(view, component_filter \\ nil) do
    html = render(view)

    # Detect Vue components in the rendered HTML
    components = find_all_vue_components(html)

    # Filter by component name if specified
    components =
      if component_filter do
        Enum.filter(components, fn {name, _} -> name == component_filter end)
      else
        components
      end

    # Print component details
    result = "\n=== Vue Components in View ==="
    result = result <> "\nTotal components found: #{length(components)}"

    result =
      Enum.reduce(components, result, fn {name, attrs, content}, acc ->
        acc <>
          "\n\n=== Component: #{name} ===" <>
          "\nAttributes: #{inspect(attrs)}" <>
          "\nContent Length: #{String.length(content)}" <>
          "\nContent Preview: #{String.slice(content, 0..100)}..."
      end)

    # Return the detailed information
    result
  end

  @spec find_all_vue_components(String.t()) :: [{String.t(), map(), String.t()}]
  defp find_all_vue_components(html) do
    # Pattern to find Vue components with their attributes
    # This looks for any tag with v-component or data-v-component attributes
    pattern = ~r/<([^>]*?)(?:v-component|data-v-component)="([^"]+)"([^>]*?)>(.*?)<\/(?:[^>]*?)>/s

    # Find all matches
    Regex.scan(pattern, html, capture: :all_but_first)
    |> Enum.map(fn [prefix, name, suffix, content] ->
      # Extract all attributes
      attrs = extract_attributes(prefix <> suffix)
      {name, attrs, content}
    end)
  end

  @spec extract_attributes(String.t()) :: map()
  defp extract_attributes(attrs_str) do
    # Pattern to extract attribute name-value pairs
    pattern = ~r/(\w+(?:-\w+)*)(?:=(['"])(.*?)\2)?/s

    Regex.scan(pattern, attrs_str, capture: :all_but_first)
    |> Enum.reduce(%{}, fn
      [name], acc -> Map.put(acc, name, true)
      [name, _, value], acc -> Map.put(acc, name, value)
    end)
  end

  @doc """
  Extracts and decodes slot content from a Vue component if it's using the
  data-v-slots format with base64 encoding.
  """
  @spec extract_slot_content(view(), String.t(), String.t()) :: String.t() | nil
  def extract_slot_content(view, component_name, slot_name \\ "default") do
    html = render(view)

    # Try to find slots attribute in the component
    case Regex.run(
           ~r/data-v-(component|vue-component)="#{component_name}"[^>]*data-v-slots=(['"])(.*?)\2/,
           html
         ) do
      [_, _, _, slots_json] ->
        try do
          slots = Jason.decode!(slots_json)

          case Map.get(slots, slot_name) do
            nil ->
              nil

            encoded_content when is_binary(encoded_content) ->
              try do
                # Attempt to decode base64 content
                Base.decode64!(encoded_content)
              rescue
                # Return as-is if not base64 encoded
                _ -> encoded_content
              end

            # Handle any other type
            other ->
              inspect(other)
          end
        rescue
          e ->
            # If JSON decoding fails, return the raw content for debugging
            "Error decoding slots: #{Exception.message(e)} - Raw: #{slots_json}"
        end

      _ ->
        nil
    end
  end
end
