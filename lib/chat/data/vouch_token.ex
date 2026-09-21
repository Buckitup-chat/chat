defmodule Chat.Data.VouchToken do
  @moduledoc "Data access for vouch_tokens."

  alias Chat.Data.Schemas.VouchToken
  alias Chat.Repo

  def get_vouch_token(kind, issuer_hash, subject_hash) do
    Repo.get_by(VouchToken, kind: kind, issuer_hash: issuer_hash, subject_hash: subject_hash)
  end

  def upsert_vouch_token(changeset) do
    Repo.insert(changeset,
      on_conflict: :replace_all,
      conflict_target: [:kind, :issuer_hash, :subject_hash]
    )
  end
end
