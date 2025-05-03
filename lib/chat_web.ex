defmodule ChatWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, views, channels and so on.

  This can be used in your application as:

      use ChatWeb, :controller
      use ChatWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """
  def static_paths do
    ~w(assets fonts frontend images favicon.ico robots.txt walc-external-bundle.js)
  end

  def controller do
    quote do
      use Phoenix.Controller, namespace: ChatWeb

      import Plug.Conn, except: [assign: 3]
      use Gettext, backend: ChatWeb.Gettext
      alias ChatWeb.Router.Helpers, as: Routes

      unquote(verified_routes())
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/chat_web/templates",
        namespace: ChatWeb

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      # Include shared imports and aliases for views
      unquote(view_helpers())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {ChatWeb.LayoutView, :live}

      unquote(view_helpers())
      unquote(live_helpers())
      unquote(socket_private_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(view_helpers())
      unquote(live_helpers())
      unquote(socket_private_helpers())
    end
  end

  def component do
    quote do
      use Phoenix.Component

      unquote(view_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      use Gettext, backend: ChatWeb.Gettext
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: ChatWeb.Endpoint,
        router: ChatWeb.Router,
        statics: ChatWeb.static_paths()
    end
  end

  defp view_helpers do
    quote do
      # Use all HTML functionality (forms, tags, etc)
      # use Phoenix.HTML
      import Phoenix.HTML.Form
      import Phoenix.HTML

      use PhoenixHTMLHelpers

      # Add support to Vue components
      use LiveVue

      # Generate component for each vue file, so you can omit v-component="name".
      # You can configure path to your components by using optional :vue_root param
      use LiveVue.Components, vue_root: ["./assets/vue", "./lib/chat_web"]

      # Import LiveView and .heex helpers (live_render, live_patch, <.form>, etc)
      import Phoenix.Component
      import ChatWeb.LiveHelpers

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View

      import ChatWeb.ErrorHelpers
      use Gettext, backend: ChatWeb.Gettext
      alias ChatWeb.Router.Helpers, as: Routes

      unquote(verified_routes())
    end
  end

  defp live_helpers do
    quote do
      defp ok(x), do: {:ok, x}

      defp noreply(x), do: {:noreply, x}

      defp reply(x, p), do: {:reply, p, x}

      defp stream_batch_insert(socket, key, items, opts \\ %{}) do
        items
        |> Enum.reduce(socket, fn item, socket ->
          stream_insert(socket, key, item, opts)
        end)
      end
    end
  end

  defp socket_private_helpers do
    quote do
      import Tools.SocketPrivate
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
