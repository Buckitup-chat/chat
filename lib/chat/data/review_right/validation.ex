defmodule Chat.Data.ReviewRight.Validation do
  @moduledoc """
  Macro for generating review right validation modules.

      defmodule Chat.Data.ReviewPostRight.Validation do
        use Chat.Data.ReviewRight.Validation, kind: :post
      end
  """

  defmacro __using__(opts) do
    kind = Keyword.fetch!(opts, :kind)
    kind_str = Atom.to_string(kind)

    schema_module =
      Module.concat([Chat.Data.Schemas, :"Review#{String.capitalize(kind_str)}Right"])

    quote do
      alias Chat.Data.Review, as: ReviewData
      alias unquote(schema_module)
      alias Chat.Data.User.Validation, as: UserValidation

      def unquote(:"validate_#{kind}_right_insert")(right_struct) do
        struct(unquote(schema_module))
        |> unquote(schema_module).create_changeset(Map.from_struct(right_struct))
        |> validate_matches_review(
          right_struct.review_hash,
          right_struct.author_hash,
          right_struct.origin_hash
        )
      end

      def unquote(:"validate_#{kind}_right_update")(existing, right_struct) do
        attrs =
          right_struct
          |> Map.from_struct()
          |> Map.take([:deleted_flag, :owner_timestamp, :sign_b64, :sign_hash])
          |> Map.reject(fn {_k, v} -> is_nil(v) end)

        existing
        |> unquote(schema_module).update_changeset(attrs)
        |> UserValidation.validate_signature()
        |> UserValidation.validate_timestamp_newer_than_existing()
      end

      defp validate_matches_review(changeset, review_hash, author_hash, origin_hash)
           when is_binary(review_hash) do
        case ReviewData.get_review(review_hash) do
          nil ->
            Ecto.Changeset.add_error(changeset, :review_hash, "review does not exist")

          review ->
            changeset
            |> check_matches(:author_hash, author_hash, review.author_hash)
            |> check_matches(:origin_hash, origin_hash, review.origin_hash)
        end
      end

      defp validate_matches_review(changeset, _review_hash, _author_hash, _origin_hash),
        do: changeset

      defp check_matches(changeset, _field, value, value), do: changeset

      defp check_matches(changeset, field, _value, _expected),
        do: Ecto.Changeset.add_error(changeset, field, "does not match review")
    end
  end
end
