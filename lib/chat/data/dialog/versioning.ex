defmodule Chat.Data.Dialog.Versioning do
  @moduledoc "Versioning for dialog_messages records."

  use Chat.Data.Versioning,
    main_schema: Chat.Data.Schemas.DialogMessage,
    version_schema: Chat.Data.Schemas.DialogMessageVersion,
    main_conflict_target: :message_id,
    version_conflict_target: [:message_id, :sign_hash],
    fields: [
      :message_id,
      :dialog_hash,
      :sender_hash,
      :content_b64,
      :deleted_flag,
      :refs_map_b64,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64,
      :sign_hash
    ],
    mutable_fields: [
      :content_b64,
      :deleted_flag,
      :refs_map_b64,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64,
      :sign_hash
    ]
end
