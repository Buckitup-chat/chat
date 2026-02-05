defmodule Chat.Data.Types.Consts do
  @moduledoc false

  def user_hash_prefix, do: <<0x01>>
  def dialog_hash_prefix, do: <<0x02>>
end
