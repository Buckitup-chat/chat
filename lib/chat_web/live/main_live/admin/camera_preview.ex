defmodule ChatWeb.MainLive.Admin.CameraPreview do
  @moduledoc "Async camera preview"
  use ChatWeb, :live_component

  alias Phoenix.LiveView.AsyncResult

  alias Chat.Sync.Camera.Sensor

  def mount(socket) do
    socket
    |> assign(:img, AsyncResult.loading())
    |> assign(:task, nil)
    |> ok()
  end

  def update(new_assigns, socket) do
    if url_changes?(new_assigns, socket.assigns) do
      stop_prev_task(socket.assigns.task)

      socket
      |> assign(new_assigns)
      |> assign_camera_task()
      |> assign(:img, AsyncResult.loading())
    else
      socket
      |> assign(new_assigns)
    end
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <span class="self-center w-12 text-center">
      <.async_result :let={img} assign={@img}>
        <:loading>...</:loading>
        <:failed>
          <span class="text-2xl">⛔</span>
          <!-- <%= @img.failed.error_reason %> -->
        </:failed>
        <img class="w-12" src={img.inline_url} />
      </.async_result>
    </span>
    """
  end

  defp url_changes?(new, old) do
    cond do
      not Map.has_key?(new, :url) -> false
      new.url != old[:url] -> true
      true -> false
    end
  end

  defp assign_camera_task(%{root_pid: pid, assigns: %{myself: cid, url: url}} = socket) do
    with false <- url == "",
         {:ok, task_pid} =
           Task.Supervisor.start_child(Chat.TaskSupervisor, generate_camera_task(url, pid, cid)) do
      socket
      |> assign(:task, task_pid)
      |> assign(:img, AsyncResult.loading())
    else
      _ -> socket |> assign(:task, nil)
    end
  end

  defp stop_prev_task(pid) do
    if is_pid(pid) and Process.alive?(pid) do
      Task.Supervisor.terminate_child(Chat.TaskSupervisor, pid)
    end
  rescue
    _ -> :error
  end

  defp generate_camera_task(url, pid, cid) do
    fn ->
      try do
        case Sensor.get_image(url) do
          {:error, reason} ->
            %AsyncResult{}
            |> AsyncResult.failed(%{error_reason: if(is_binary(reason), do: reason)})

          {:ok, {type, content}} ->
            %AsyncResult{}
            |> AsyncResult.ok(%{inline_url: "data:#{type};base64,#{Base.encode64(content)}"})
        end
        |> then(&send_update(pid, cid, img: &1))
      rescue
        _ -> :ok
      end
    end
  end
end
