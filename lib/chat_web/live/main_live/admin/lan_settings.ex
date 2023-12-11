defmodule ChatWeb.MainLive.Admin.LanSettings do
  @moduledoc "Network settings"
  use ChatWeb, :live_component

  alias ChatWeb.MainLive.Page.AdminPanel

  def mount(socket) do
    request_platform_ip()
    request_platform_known_profiles()
    request_platform_profile()

    socket
    |> assign(:ip, :requested)
    |> assign(:known_profiles, :requested)
    |> assign(:profile, :requested)
    |> ok()
  end

  def update(new, socket) do
    case new do
      %{known_profiles: list} -> %{known_profiles: make_labeled_list(list)}
      x -> x
    end
    |> then(&assign(socket, &1))
    |> ok()
  end

  def handle_event("change-profile", %{"mode" => profile}, socket) do
    set_platform_profile(profile |> String.to_existing_atom())
    request_platform_profile()

    socket
    |> assign(:profile, :requested)
    |> noreply()
  end

  def render(assigns) do
    ~H"""
    <div>
      <.current_ip ip={@ip} />
      <.current_profile selected={@profile} list={@known_profiles} myself={@myself} />
    </div>
    """
  end

  attr :ip, :any, required: true

  def current_ip(assigns) do
    ~H"""
    <section class="my-2">
      <label class="text-black/50"> IP: </label>
      <%= if @ip == :requested do %>
        loading...
      <% else %>
        <%= @ip %>
      <% end %>
    </section>
    """
  end

  attr :selected, :atom, required: true
  attr :list, :any, required: true
  attr :myself, :any, required: true

  defp current_profile(assigns) do
    ~H"""
    <section>
      <label class="text-black/50"> Mode: </label>
      <%= if @selected == :requested or @list == :requested do %>
        loading...
      <% else %>
        <form phx-change="change-profile" phx-target={@myself}>
          <select name="mode">
            <%= for {value, label} <- @list do %>
              <option selected={value == @selected} value={value}><%= label %></option>
            <% end %>
          </select>
        </form>
      <% end %>
    </section>
    """
  end

  defp request_platform_ip, do: AdminPanel.request_platform(:lan_ip)
  defp request_platform_profile, do: AdminPanel.request_platform(:lan_profile)
  defp request_platform_known_profiles, do: AdminPanel.request_platform(:lan_known_profiles)
  defp set_platform_profile(profile), do: AdminPanel.request_platform({:lan_set_profile, profile})

  defp make_labeled_list(list) do
    list
    |> Enum.map(&{&1, &1 |> Phoenix.Naming.humanize()})
  end
end
