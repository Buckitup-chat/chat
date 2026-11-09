defmodule Chat.Data.Types.DialogHash do
  @moduledoc "Dialog identifier derived from sorted participant hashes. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.dialog_prefix()
end
