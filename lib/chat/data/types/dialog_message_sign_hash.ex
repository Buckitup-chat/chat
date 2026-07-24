defmodule Chat.Data.Types.DialogMessageSignHash do
  @moduledoc "Signature hash identifying a specific version of a dialog message. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.dialog_message_sign_prefix()
end
