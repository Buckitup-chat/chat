defmodule Chat.Data.Shapes.ReviewRevokeRight do
  @moduledoc "Shape behaviour implementation for review_revoke_right."

  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRevokeRight.Validation
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias EnigmaPq

  use Chat.Data.Shapes.Shape,
    persist: [
      upsert: &RevokeRightData.upsert_revoke_right/1,
      get: &RevokeRightData.get_revoke_right/1,
      lookup_key: :review_hash,
      validate_insert: &Validation.validate_revoke_right_insert/1,
      validate_update: &Validation.validate_revoke_right_update/2
    ]

  use Toolbox.OriginLog

  @impl true
  def shape_name, do: :review_revoke_right

  @impl true
  def schema_module, do: ReviewRevokeRight

  @impl true
  def sync_required_parents(_op, %{author_hash: ah}) do
    [{:user_card, ah}]
  end

  @impl true
  def sync_derive_fields(%ReviewRevokeRight{sign_b64: sign_b64} = right)
      when is_binary(sign_b64) do
    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> ReviewRevokeRightSignHash.from_binary()

    %{right | sign_hash: sign_hash}
  end

  def sync_derive_fields(right), do: right
end
