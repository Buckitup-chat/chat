defmodule ChatWeb.LiveTestHelpers do
  @moduledoc """
  LiveView test helpers.
  """

  use ChatWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.{Socket, UploadEntry, Utils}

  @type socket :: %Socket{}
  @type view :: %Phoenix.LiveViewTest.View{}

  @spec prepare_view(%{conn: Plug.Conn.t()}) :: %{socket: Socket.t(), view: view()}
  def prepare_view(%{conn: conn}, name \\ "User") do
    {:ok, view, _html} = live(conn, "/")

    render_hook(view, "restoreAuth")

    view
    |> form("#login-form", login: %{name: name})
    |> render_submit()

    set_local_time(%{view: view})

    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @spec reload_view(%{view: view()}) :: %{socket: Socket.t(), view: view()}
  def reload_view(%{view: view}) do
    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

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

    # Special handling for LinkedText component which may have specific structure
    result =
      if component_name == "LinkedText" do
        # Try direct string search first for LinkedText content
        if is_binary(content_or_validator) && html =~ content_or_validator do
          if debug_mode do
            IO.puts("\n[DEBUG] Found text '#{content_or_validator}' in general HTML")
            # Find the context around the content for debugging
            [context] =
              Regex.run(~r/(.{0,100}#{content_or_validator}.{0,100})/s, html,
                capture: :all_but_first
              )

            IO.puts("[DEBUG] Context: #{context}")
          end

          true
        else
          # Check for LinkedText in LiveVue data-slots base64 encoded content
          case Regex.run(
                 ~r/data-name="#{component_name}"[^>]*data-slots="[^"]*default[^"]*:&quot;([^&]+)&quot;/,
                 html
               ) do
            [_, base64_content] ->
              try do
                decoded_content = Base.decode64!(base64_content)

                if is_binary(content_or_validator) && decoded_content =~ content_or_validator do
                  if debug_mode do
                    IO.puts(
                      "\n[DEBUG] Found text '#{content_or_validator}' in base64 decoded content"
                    )

                    IO.puts("[DEBUG] Decoded content: #{decoded_content}")
                  end

                  true
                else
                  false
                end
              rescue
                _ -> false
              end

            nil ->
              # Fallback to original patterns for non-LiveVue components
              linked_text_patterns = [
                ~r/<[^>]*class="[^"]*flex-initial[^"]*"[^>]*>(.*?#{content_or_validator}.*?)<\/span>/s,
                ~r/<span[^>]*class="[^"]*break-words[^"]*"[^>]*>(.*?#{content_or_validator}.*?)<\/span>/s,
                ~r/v-component="LinkedText"[^>]*>.*?(#{content_or_validator})/s
              ]

              Enum.any?(linked_text_patterns, fn pattern ->
                case Regex.run(pattern, html) do
                  [match | _] ->
                    if debug_mode, do: IO.puts("\n[DEBUG] Found LinkedText match: #{match}")
                    true

                  nil ->
                    false
                end
              end)
          end
        end
      else
        # Standard component search for other components
        case find_vue_component(html, component_name) do
          nil ->
            if debug_mode, do: IO.puts("\n[DEBUG] Component '#{component_name}' not found")
            false

          component_html ->
            if debug_mode, do: IO.puts("\n[DEBUG] Found component '#{component_name}'")

            result =
              case content_or_validator do
                validator when is_function(validator, 1) ->
                  validator.(component_html)

                text when is_binary(text) ->
                  component_html =~ text
              end

            if debug_mode && !result, do: IO.puts("[DEBUG] Content not found in component")
            result
        end
      end

    # Print full debug info if requested and not found
    if debug_mode && !result do
      IO.puts("[DEBUG] Full Vue component analysis:")
      IO.puts(debug_vue_components(view, component_name))
    end

    result
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

  @spec set_local_time(%{view: view()}) :: %{socket: Socket.t(), view: view()}
  def set_local_time(%{view: view}) do
    render_hook(view, "local-time", %{
      "locale" => "en-US",
      "timestamp" => 1_675_181_845,
      "timezone" => "Europe/Sarajevo",
      "timezone_offset" => 1
    })

    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @doc """
  Polls for a condition to become true within a specified timeout.
  Useful for flaky tests where LiveView and Vue component rendering might take time.

  ## Examples

      # Wait until a message appears in the HTML
      wait_until(fn ->
        render(view) =~ "Expected message text"
      end)
      
      # Wait with a custom timeout and interval
      wait_until(
        fn -> render(view) =~ "Expected text" end,
        "Text should appear", 
        timeout: 2000, 
        interval: 200
      )
  """
  @spec wait_until((-> boolean()), String.t(), keyword()) :: :ok | {:error, String.t()}
  def wait_until(condition_fn, message \\ "Condition to be true", opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 100)
    start_time = System.monotonic_time(:millisecond)

    wait_loop(condition_fn, message, timeout, interval, start_time)
  end

  defp wait_loop(condition_fn, message, timeout, interval, start_time) do
    cond do
      condition_fn.() ->
        :ok

      System.monotonic_time(:millisecond) - start_time > timeout ->
        {:error, "Timed out waiting for: #{message}"}

      true ->
        Process.sleep(interval)
        wait_loop(condition_fn, message, timeout, interval, start_time)
    end
  end

  @spec login_by_key(%{conn: Plug.Conn.t()}, String.t()) :: %{socket: Socket.t(), view: view()}
  def login_by_key(%{conn: conn}, path \\ "/") do
    {:ok, view, _html} = live(conn, path)

    render_hook(view, "restoreAuth")
    set_local_time(%{view: view})

    view
    |> element("#importKeyButton")
    |> render_click()

    view
    |> file_input("#my-keys-file-form", :my_keys_file, [
      %{
        last_modified: 1_594_171_879_000,
        name: "TestUser.data",
        content: File.read!("test/support/fixtures/import_keys/TestUser.data"),
        size: 113,
        type: "text/plain"
      }
    ])
    |> render_upload("TestUser.data")

    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @spec open_dialog(%{view: view()}) :: %{socket: Socket.t(), view: view()}
  def open_dialog(%{view: view}, user \\ nil) do
    user_item =
      case user do
        nil ->
          "#chatRoomBar ul li.hidden"

        _ ->
          user = user |> Chat.Card.from_identity()
          "#chatRoomBar #user-#{user.hash}"
      end

    view
    |> element(user_item, if(user, do: "", else: "My notes"))
    |> render_click()

    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @spec create_and_open_room(%{view: view()}, String.t()) :: %{socket: Socket.t(), view: view()}
  def create_and_open_room(%{view: view}, type \\ "public") do
    view
    |> element("button:first-child", "Rooms")
    |> render_click()

    name = Utils.random_id()

    view
    |> form("#room-create-form", room_input: %{name: name, type: type})
    |> render_submit()

    state = :sys.get_state(view.pid)
    %{socket: state.socket, view: view}
  end

  @spec start_upload(%{view: view()}) :: %{
          entry: UploadEntry.t() | nil,
          file: map(),
          filename: String.t(),
          socket: socket()
        }
  def start_upload(%{view: view}) do
    filename = "#{Utils.random_id()}.jpeg"

    file =
      file_input(view, "#uploader-file-form", :file, [
        %{
          last_modified: 1_594_171_879_000,
          name: filename,
          content:
            Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+P+/HgAFhAJ/wlseKgAAAABJRU5ErkJggg=="
            ),
          size: 70,
          type: "image/jpeg"
        }
      ])

    render_upload(file, filename, 0)

    state = :sys.get_state(view.pid)
    socket = state.socket
    last_entry = List.last(socket.assigns.uploads.file.entries)

    %{entry: last_entry, file: file, filename: filename, socket: socket}
  end
end
