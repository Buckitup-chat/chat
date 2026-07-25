defmodule Chat.Data.Types.DialogMessageReceiptHash do
  @moduledoc "Hash identifying a dialog message receipt. Custom Ecto type."

  use Chat.Data.Types.PrefixedHash, prefix: Chat.Data.Types.Consts.dialog_message_receipt_prefix()
end
