defmodule ChatWeb.Telemetry do
  @moduledoc false
  use Supervisor
  import Telemetry.Metrics

  alias Chat.Measurements.CPUStatus

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # CPU Metrics
      summary("cpu.utilization.idle",
        reporter_options: [nav: "CPU"],
        description: """
        The idle state of the CPU denotes periods when the processor is not executing any instructions and is available for new tasks. 
        During this state, the CPU is not engaged in computational work
        """
      ),
      summary("cpu.utilization.non_idle",
        reporter_options: [nav: "CPU"],
        description: """
        The non-idle state signifies the time when the CPU is actively involved in executing tasks and processes. 
        It encompasses both user processes and system processes, including the operating system's kernel and device drivers.
        """
      ),
      summary("cpu.utilization.iowait",
        reporter_options: [nav: "CPU"],
        description: """
        Iowait refers to the time when the CPU is idle but waiting for input/output (I/O) operations to finish, 
         particularly during data transfers to or from storage devices. 
        It represents the CPU's idle time due to I/O activities.
        """
      ),
      summary("cpu.temperature.value", reporter_options: [nav: "CPU"])
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      {CPUStatus, :track_temperature, []},
      {CPUStatus, :track_utilization, []}
    ]
  end
end
