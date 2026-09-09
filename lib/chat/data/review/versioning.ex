defmodule Chat.Data.Review.Versioning do
  @moduledoc "Versioning for review records."

  use Chat.Data.Versioning,
    main_schema: Chat.Data.Schemas.Review,
    version_schema: Chat.Data.Schemas.ReviewVersion,
    main_conflict_target: :review_hash,
    version_conflict_target: [:review_hash, :sign_hash],
    fields: [
      :review_hash,
      :origin_hash,
      :author_hash,
      :content_b64,
      :deleted_flag,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64,
      :sign_hash
    ],
    mutable_fields: [
      :content_b64,
      :deleted_flag,
      :parent_sign_hash,
      :owner_timestamp,
      :sign_b64,
      :sign_hash
    ]
end
