defmodule Chat.NetworkSynchronization do
  @moduledoc "Network synchronisation"

#  alias Chat.NetworkSynchronization.Source

#  def synchronizations do
#    load_sources()
#    |> zip(load_status())
#  end
#  def add_source do
#    get_max_id()
#    |> Kernel.+(1)
#    |> Source.new()
#    |> save_source()
#  end
#  def start_source(id) do
#
#  end
#  def stop_source do  end
#  def update_source do  end
#  def remove_source do  end
#
#  def init_workers do  end
#  def start_children(source) do  end
#  def stop_children(source) do  end

  def monotonic_ms, do: System.monotonic_time(:millisecond)
end
