defmodule Chat.Measurements.CPUStatus do
  @moduledoc false

  def track_temperature do
    with {:ok, content} <- File.read("/sys/class/thermal/thermal_zone0/temp"),
         {millidegree_c, _} <- Integer.parse(content) do
      :telemetry.execute([:cpu, :temperature], %{value: millidegree_c / 1000})
    else
      _error -> :error
    end
  end

  def track_utilization do
    with {:ok, content} <- File.read("/proc/stat"),
         data <-
           content
           |> String.split("\n")
           |> List.first()
           |> String.split()
           |> List.pop_at(0)
           |> elem(1)
           |> Enum.map(&String.to_integer/1),
         stat <-
           Enum.zip(~w(user nice system idle iowait irq softirq steal guest guest_nice)a, data)
           |> Map.new() do
      total = Enum.sum(data)
      idle = stat.idle / total
      non_idle = (total - stat.idle) / total
      iowait = stat.iowait / total

      :telemetry.execute([:cpu, :utilization], %{idle: idle})
      :telemetry.execute([:cpu, :utilization], %{non_idle: non_idle})
      :telemetry.execute([:cpu, :utilization], %{iowait: iowait})
    else
      _error -> :error
    end
  end
end
