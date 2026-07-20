defmodule Chat.Data.Shapes.ReviewPublicPasswords do
  @moduledoc "Shape behaviour implementation for review_public_passwords."

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.ReviewPublicPassword, as: ReviewPublicPasswordData
  alias Chat.Data.ReviewPublicPassword.Validation
  alias Chat.Data.Schemas.ReviewPublicPassword
  alias Chat.Data.Types.ReviewPasswordSignHash
  alias EnigmaPq
  @impl true
  def shape_name, do: :review_public_passwords

  @impl true
  def schema_module, do: ReviewPublicPassword

  @impl true
  def sync_required_parents(_op, %{author_hash: ah}) do
    [{:user_card, ah}]
  end

  @impl true
  def sync_derive_fields(%ReviewPublicPassword{sign_b64: sign_b64} = rp)
      when is_binary(sign_b64) do
    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> ReviewPasswordSignHash.from_binary()

    %{rp | sign_hash: sign_hash}
  end

  def sync_derive_fields(rp), do: rp

  @impl true
  def sync_persist(operation, rp) do
    case operation do
      :insert ->
        rp
        |> Validation.validate_review_public_password_insert()
        |> persist_insert(rp)

      :update ->
        {:ok, rp}
    end
  end

  @impl true
  def ingest_configure_writer(writer, _user_pop_context), do: writer

  defp persist_insert(changeset, rp) do
    case changeset do
      %{valid?: true} ->
        ReviewPublicPasswordData.upsert_review_public_password(changeset)

      %{valid?: false} = cs ->
        log("Invalid review_public_password insert: #{inspect(cs.errors)}", :warning)
        {:ok, rp}
    end
  end
end
