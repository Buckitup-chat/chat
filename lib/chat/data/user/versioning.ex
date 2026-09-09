defmodule Chat.Data.User.Versioning do
  @moduledoc "Versioning for user_storage records."

  use Chat.Data.Versioning,
    main_schema: Chat.Data.Schemas.UserStorage,
    version_schema: Chat.Data.Schemas.UserStorageVersion,
    main_conflict_target: [:user_hash, :uuid],
    version_conflict_target: [:user_hash, :uuid, :sign_hash],
    fields: [
      :user_hash,
      :uuid,
      :value_b64,
      :deleted_flag,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64,
      :sign_hash
    ],
    mutable_fields: [
      :value_b64,
      :deleted_flag,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64,
      :sign_hash
    ]
end
