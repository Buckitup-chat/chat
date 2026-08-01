defmodule Chat.Data.ReviewRight do
  @moduledoc """
  Macro for generating review right context modules.

  Collapses the post/revoke right pair — schema, context, validation,
  and sign-hash type are structurally identical and differ only by kind.

      defmodule Chat.Data.ReviewPostRight do
        use Chat.Data.ReviewRight, kind: :post
      end
  """

  defmacro __using__(opts) do
    kind = Keyword.fetch!(opts, :kind)
    kind_str = Atom.to_string(kind)

    schema_module =
      Module.concat([Chat.Data.Schemas, :"Review#{String.capitalize(kind_str)}Right"])

    quote do
      import Chat.Db, only: [repo: 0]
      import Ecto.Query

      alias unquote(schema_module)

      def unquote(:"get_#{kind}_right")(review_hash) do
        repo().get(unquote(schema_module), review_hash)
      end

      def unquote(:"upsert_#{kind}_right")(changeset) do
        repo().insert(changeset,
          on_conflict: upsert_query(),
          conflict_target: :review_hash,
          allow_stale: true
        )
      end

      defp upsert_query do
        from(r in unquote(schema_module),
          update: [
            set: [
              deleted_flag: fragment("EXCLUDED.deleted_flag"),
              owner_timestamp: fragment("EXCLUDED.owner_timestamp"),
              sign_b64: fragment("EXCLUDED.sign_b64"),
              sign_hash: fragment("EXCLUDED.sign_hash")
            ]
          ],
          where:
            is_nil(r.owner_timestamp) or
              r.owner_timestamp < fragment("EXCLUDED.owner_timestamp")
        )
      end
    end
  end
end
