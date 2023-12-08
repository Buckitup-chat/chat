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
    |> then(& assign(socket, &1))
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div>
      <.current_ip ip={@ip} />
      <.current_profile selected={@profile} list={@known_profiles} />
    </div>
    """
  end

  attr :ip, :any, required: true

  def current_ip(assigns) do
    ~H"""
    <section>
      IP:
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

  defp current_profile(assigns) do
    ~H"""
    <section>
      Mode:
              <%= if @selected == :requested or @list == :requested do %>
                loading...
              <% else %>
      <select name="mode" >
      <%= for {value, label} <- @list do %>
        <option selected={value == @selected} value={value}><%= label %></option>
      <% end %>
      </select>
              <% end %>
    </section>
"""
  end


  defp request_platform_ip, do: AdminPanel.request_platform(:lan_ip)
  defp request_platform_profile, do: AdminPanel.request_platform(:lan_profile)
  defp request_platform_known_profiles, do: AdminPanel.request_platform(:lan_known_profiles)


  defp make_labeled_list(list) do
    list
    |> Enum.map(& {&1, &1 |> Phoenix.Naming.humanize()})
  end
  
end
