defmodule Chat.Data.Types.DialogMessageReactionHash do
  @moduledoc "Keyed MAC hash identifying a dialog message reaction. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash,
    prefix: Consts.dialog_message_reaction_prefix()
end
