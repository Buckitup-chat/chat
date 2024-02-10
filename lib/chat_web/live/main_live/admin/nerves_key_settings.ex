defmodule ChatWeb.MainLive.Admin.NervesKeySettings do
  @moduledoc "Nerves key status & settings"
  use ChatWeb, :live_component

  def mount(socket) do
    request_status(self())

    socket
    |> assign(:status, :loading)
    |> assign(:show_provision_form, nil)
    |> ok()
  end

  def handle_event("provision_form_submit", params, %{assigns: %{actor: actor}} = socket) do
    years = params["years"] |> String.to_integer()
    name = params["name"] |> String.trim()
    request_provisioning(self(), actor, name, years)

    socket
    |> assign(:status, :loading)
    |> assign(:show_provision_form, nil)
    |> noreply()
  end

  def render(assigns) do
    ~H"""
    <div>
      <.status status={@status} />
      <%= if @show_provision_form do %>
        <.provision_form target={@myself} />
      <% end %>
    </div>
    """
  end

  def status(assigns) do
    ~H"""
    <section class="t-networks my-2">
      <%= if @status == :loading do %>
        Loading...
      <% else %>
        <%= @status %>
      <% end %>
    </section>
    """
  end

  def status_no_chip(assigns) do
    ~H"""
    <div class="text-center my-2">
      No <a href="https://github.com/nerves-hub/nerves_key" tagret="_blank">chip</a> detected
    </div>
    """
  end

  def status_not_provisioned(assigns) do
    ~H"""
    <div class="text-center my-2">
      Chip found. Not provisioned
    </div>
    <div>
      <label class="text-black/50"> Board: </label>
      <%= @board_name %>
    </div>
    <div>
      <label class="text-black/50"> SN: </label>
      <%= @manufacturer_sn %>
    </div>
    """
  end

  def provision_form(assigns) do
    ~H"""
    <section>
      <form phx-submit="provision_form_submit" phx-target={@target}>
        <div>
          <input type="text" placeholder="Device name" name="name" class="w-full rounded my-1 py-1.5" />
        </div>
        <div>
          Valid for
          <input
            type="number"
            min="1"
            max="1000"
            name="years"
            value="100"
            class="rounded p-1 border-0"
          /> years
        </div>
        <div class="">
          <button class="h-11 px-10 mt-2 text-white border-0 rounded-lg bg-grayscale flex items-center justify-center">
            Provision
          </button>
        </div>
      </form>
    </section>
    """
  end

  @topic Application.compile_env!(:chat, :topic_to_nerveskey)

  def request_status(my_pid) do
    @topic
    |> pubsub_async_command(:status, fn ->
      # assigns = %{board_name: "NervesKey", manufacturer_sn: "AER5WYW6655PL3Q"}
      #
      # %{status: status_not_provisioned(assigns), show_provision_form: true}
      # |> update_component(my_pid)

      # %{status: status_no_chip(%{})} |> update_component(my_pid)
      receive do
        {:status, :no_chip} ->
          %{status: status_no_chip(%{})} |> update_component(my_pid)
          :ok

        {:status, {:not_provisioned, assigns}} ->
          %{status: status_not_provisioned(assigns), show_provision_form: true}
          |> update_component(my_pid)

          :ok
      after
        # :timeout
        1500 ->
          %{status: status_no_chip(%{})} |> update_component(my_pid)
      end
    end)
  end

  def request_provisioning(component_pid, actor, _device_name, cert_years) do
    pubsub_async_command(@topic, {:generate_cert, cert_years}, fn ->
      with {:ok, cert_and_key} <- receive_cert_and_key(5 |> :timer.seconds()),
           _ <- save_cert_to_my_notes(actor, cert_and_key) do
        # hash <- calc_keys_hash(cert_and_key),
        # :ok <- send_provision_ready(@topic, hash, device_name),
        # :ok <- receive_provisioned(15 |> :timer.seconds()) do
        request_status(component_pid)
      else
        _ -> request_status(component_pid)
      end
    end)
  end

  defp receive_cert_and_key(timeout) do
    receive do
      {:cert, cert_and_key} -> {:ok, cert_and_key}
    after
      timeout -> :timeout
    end
  end

  defp save_cert_to_my_notes(actor, cert_and_key) do
    require Logger
    actor |> inspect(pretty: true) |> Logger.critical()
    cert_and_key |> inspect(pretty: true) |> Logger.critical()

    :todo
  end

  # defp calc_keys_hash(cert_and_key) do
  #   :todo
  # end
  #
  # defp send_provision_ready(topic, hash, device_name) do
  #   broadcast_command(topic, {{:provision, hash, device_name}, self()})
  #
  #   :ok
  # end
  #
  # defp receive_provisioned(timeout) do
  #   receive do
  #     {:provisioned, data} ->
  #       data |> dbg()
  #       :ok
  #   after
  #     timeout ->
  #       :timeout
  #   end
  # end

  # generate_keys
  # send_keys_to_my_notes
  # calc_keys_hash
  # finish_provisoning

  defp update_component(updates_map, pid) do
    updates_map
    |> Map.put(:id, :nerveskey_settings)
    |> then(&send_update(pid, __MODULE__, &1))
  end

  defp pubsub_async_command(topic, command, action) do
    Task.start(fn ->
      broadcast_command(topic, {command, self()})

      action.()
    end)
  end

  defp broadcast_command(topic, command) do
    Phoenix.PubSub.broadcast(Chat.PubSub, topic, command)
  end
end
