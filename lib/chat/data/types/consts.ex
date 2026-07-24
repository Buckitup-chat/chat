defmodule Chat.Data.Types.Consts do
  @moduledoc false

  @deprecated "Use user_prefix/0 instead"
  def user_hash_prefix, do: <<0x01>>

  @deprecated "Use dialog_prefix/0 instead"
  def dialog_hash_prefix, do: <<0x02>>

  def user_prefix, do: "u_"
  def user_storage_sign_prefix, do: "uss_"
  def dialog_prefix, do: "di_"
  def dialog_message_prefix, do: "dmsg_"
  def dialog_message_sign_prefix, do: "dms_"
  def dialog_message_reaction_prefix, do: "dmr_"
  def dialog_message_receipt_prefix, do: "dmrc_"
  def file_prefix, do: "f_"
  def origin_sign_prefix, do: "ors_"
  def review_prefix, do: "rv_"
  def review_sign_prefix, do: "rvs_"
  def review_password_sign_prefix, do: "rvps_"
  def review_post_right_sign_prefix, do: "rvprs_"
  def review_revoke_right_sign_prefix, do: "rvrrs_"
  def review_list_sign_prefix, do: "rvls_"
end
