defmodule Chat.Data.Types.DialogMessageReceiptHash do
  @moduledoc "Hash identifying a dialog message receipt. Custom Ecto type."

  alias Chat.Data.Types.Consts

  use Chat.Data.Types.PrefixedHash, prefix: Consts.dialog_message_receipt_prefix()
end
