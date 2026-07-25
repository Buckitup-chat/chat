defmodule Chat.Data.Types.DialogHash do
  @moduledoc "Dialog identifier derived from sorted participant hashes. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.dialog_prefix()
end
