defmodule ChatWeb.ElectricLive.ModerationSandboxLive.Settings do
  @moduledoc "LiveView component for origin settings management within the origin sandbox."

  use Phoenix.Component

  alias ChatWeb.ElectricLive.ModerationSandboxLive.SettingsClient

  @known_keys [
    {"review_access", "open / invite_only", "open"},
    {"review_token_ttl_days", "integer 1..365", "7"},
    {"auth_token", "min 16 chars", ""},
    {"google_review_url", "URL string", ""},
    {"review_greeting", "text", ""}
  ]

  def load_settings(origin_hash, base_url, auth) do
    case SettingsClient.list_settings(origin_hash, base_url, auth) do
      {:ok, settings, _logs} -> settings
      {:error, _reason, _logs} -> []
    end
  end

  def handle_event("refresh_settings", _params, socket, base_url, auth) do
    settings = load_settings(socket.assigns.identity.origin_hash, base_url, auth)
    {:noreply, assign(socket, origin_settings: settings)}
  end

  def handle_event("setting_form_change", %{"key" => key} = params, socket, _base_url, _auth) do
    value =
      if key != socket.assigns.setting_form_key do
        lookup_current_value(key, socket.assigns.origin_settings)
      else
        params["value"] || default_value_for_key(key)
      end

    {:noreply,
     assign(socket, setting_form_key: key, setting_form_value: value, setting_form_open: true)}
  end

  def handle_event("set_setting", %{"key" => key, "value" => value}, socket, base_url, auth) do
    identity = socket.assigns.identity
    existing = Enum.find(socket.assigns.origin_settings, &(&1.key == key))

    SettingsClient.set_setting(
      identity.origin_hash,
      key,
      value,
      existing,
      identity.sign_skey,
      base_url
    )
    |> apply_result(socket, base_url, auth)
  end

  def handle_event("tombstone_setting", %{"key" => key}, socket, base_url, auth) do
    identity = socket.assigns.identity

    case Enum.find(socket.assigns.origin_settings, &(&1.key == key)) do
      nil ->
        {:noreply, assign(socket, error_message: "Setting not found")}

      setting ->
        SettingsClient.tombstone_setting(setting, identity.sign_skey, base_url)
        |> apply_result(socket, base_url, auth)
    end
  end

  defp apply_result({:ok, %{log_entries: logs}}, socket, base_url, auth) do
    settings = load_settings(socket.assigns.identity.origin_hash, base_url, auth)

    {:noreply,
     socket
     |> assign(origin_settings: settings, setting_form_open: true)
     |> update(:request_log, &(logs ++ &1))}
  end

  defp apply_result({:error, %{reason: reason, log_entries: logs}}, socket, _base_url, _auth) do
    {:noreply, socket |> assign(error_message: reason) |> update(:request_log, &(logs ++ &1))}
  end

  defp default_value_for_key(key) do
    case Enum.find(@known_keys, fn {k, _, _} -> k == key end) do
      {_, _, default} -> default
      nil -> ""
    end
  end

  defp lookup_current_value(key, origin_settings) do
    case Enum.find(origin_settings, &(&1.key == key && !&1.deleted_flag)) do
      %{value: value} -> value
      nil -> default_value_for_key(key)
    end
  end

  def render_settings_section(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <div class="flex justify-between items-center mb-4">
        <h2 class="text-lg font-semibold text-gray-900">Settings</h2>
        <button
          phx-click="refresh_settings"
          class="px-3 py-1 bg-gray-200 text-gray-700 rounded text-sm hover:bg-gray-300"
        >
          Refresh
        </button>
      </div>

      {render_settings_list(assigns)}
      {render_setting_form(assigns)}
    </div>
    """
  end

  defp render_settings_list(assigns) do
    ~H"""
    <%= if @origin_settings == [] do %>
      <p class="text-sm text-gray-500">No settings configured for this origin.</p>
    <% else %>
      <div class="space-y-2">
        <div
          :for={setting <- @origin_settings}
          class={"flex items-center justify-between p-3 rounded border #{if setting.deleted_flag, do: "border-red-200 bg-red-50", else: "border-gray-200"}"}
        >
          <div class="text-sm">
            <span class="font-medium">{setting.key}</span>
            <span class="text-gray-600 ml-2">= {setting.value}</span>
            <%= if setting.deleted_flag do %>
              <span class="text-red-500 ml-2">[deleted]</span>
            <% end %>
          </div>
          <button
            :if={!setting.deleted_flag}
            phx-click="tombstone_setting"
            phx-value-key={setting.key}
            class="px-3 py-1 bg-red-600 text-white rounded text-sm hover:bg-red-700"
          >
            Delete
          </button>
        </div>
      </div>
    <% end %>
    """
  end

  defp render_setting_form(assigns) do
    assigns = do_assign_new(assigns, :known_keys, fn -> @known_keys end)

    ~H"""
    <details class="mt-4" open={@setting_form_open}>
      <summary class="cursor-pointer text-sm font-medium text-gray-700">
        Set a Setting
      </summary>
      <form phx-submit="set_setting" phx-change="setting_form_change" class="mt-3 space-y-3">
        <div>
          <label class="block text-xs font-medium text-gray-700 mb-1">Key</label>
          <select
            name="key"
            class="w-full px-3 py-2 border rounded-lg text-sm"
            value={@setting_form_key}
          >
            <option
              :for={{key, hint, _default} <- @known_keys}
              value={key}
              selected={key == @setting_form_key}
            >
              {key} ({hint})
            </option>
          </select>
        </div>
        <div>
          <label class="block text-xs font-medium text-gray-700 mb-1">Value</label>
          <input
            type="text"
            name="value"
            value={@setting_form_value}
            required
            class="w-full px-3 py-2 border rounded-lg text-sm"
          />
        </div>
        <button
          type="submit"
          class="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 text-sm"
        >
          Set
        </button>
      </form>
    </details>
    """
  end

  defp do_assign_new(assigns, key, fun) do
    if Map.has_key?(assigns, key), do: assigns, else: Map.put(assigns, key, fun.())
  end
end
