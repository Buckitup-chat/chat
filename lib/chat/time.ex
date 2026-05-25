defmodule Chat.Time do
  @moduledoc deprecated: "Use Chat.TimeKeeper directly"

  defdelegate now(), to: Chat.TimeKeeper
  defdelegate now_unix(), to: Chat.TimeKeeper
  defdelegate monotonic_offset(unix_timestamp), to: Chat.TimeKeeper
  defdelegate monotonic_to_unix(offset), to: Chat.TimeKeeper
  defdelegate set_time(time), to: Chat.TimeKeeper
  defdelegate set_initial_system_time(), to: Chat.TimeKeeper
  defdelegate update_time(unix_timestamp), to: Chat.TimeKeeper
end
