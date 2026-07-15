defmodule Chat.Data.Types.DialogMessageReactionHash do
  @moduledoc "Keyed MAC hash identifying a dialog message reaction. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.dialog_message_reaction_prefix()
end
