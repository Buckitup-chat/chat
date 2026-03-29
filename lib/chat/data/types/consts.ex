defmodule Chat.Data.Types.Consts do
  @moduledoc false

  @deprecated "Use user_prefix/0 instead"
  def user_hash_prefix, do: <<0x01>>

  @deprecated "Use dialog_prefix/0 instead"
  def dialog_hash_prefix, do: <<0x02>>

  def user_prefix, do: "u_"
  def user_storage_sign_prefix, do: "uss_"
end
