defmodule Chat.Data.Types.ConstsTest do
  use ExUnit.Case, async: true

  alias Chat.Data.Types.Consts

  @prefixes [
    user_prefix: "u_",
    user_storage_sign_prefix: "uss_",
    dialog_prefix: "di_",
    dialog_message_prefix: "dmsg_",
    dialog_message_sign_prefix: "dms_",
    dialog_message_reaction_prefix: "dmr_",
    dialog_message_receipt_prefix: "dmrc_",
    file_prefix: "f_",
    file_chunk_data_prefix: "fd_",
    origin_sign_prefix: "ors_",
    review_prefix: "rv_",
    review_sign_prefix: "rvs_",
    review_password_sign_prefix: "rvps_",
    review_post_right_sign_prefix: "rvprs_",
    review_revoke_right_sign_prefix: "rvrrs_",
    review_list_sign_prefix: "rvls_",
    origin_bot_sign_prefix: "ob_",
    review_write_token_sign_prefix: "rwt_",
    review_write_token_nonce_prefix: "rwn_",
    origin_order_prefix: "org_ord_"
  ]

  # apply/3 keeps the compiler from warning about these deprecated accessors
  @legacy_prefixes [user_hash_prefix: <<0x01>>, dialog_hash_prefix: <<0x02>>]

  test "every string prefix accessor returns its prefix" do
    for {accessor, prefix} <- @prefixes do
      assert apply(Consts, accessor, []) == prefix, "#{accessor}/0"
    end
  end

  test "string prefixes are unique" do
    values = Keyword.values(@prefixes)
    assert values == Enum.uniq(values)
  end

  test "legacy binary prefix accessors" do
    for {accessor, prefix} <- @legacy_prefixes do
      assert apply(Consts, accessor, []) == prefix, "#{accessor}/0"
    end
  end

  test "the table covers every public accessor" do
    accessors = Consts.__info__(:functions) |> Keyword.keys() |> Enum.sort()
    listed = (@prefixes ++ @legacy_prefixes) |> Keyword.keys() |> Enum.sort()
    assert accessors == listed
  end
end
