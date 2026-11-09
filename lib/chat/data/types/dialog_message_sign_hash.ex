defmodule Chat.Data.Types.DialogMessageSignHash do
  @moduledoc "Signature hash identifying a specific version of a dialog message. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.dialog_message_sign_prefix()
end
