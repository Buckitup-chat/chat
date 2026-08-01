defmodule Chat.Data.Shapes.ReviewPostRight do
  @moduledoc "Shape behaviour implementation for review_post_right."

  alias Chat.Data.ReviewPostRight, as: PostRightData
  alias Chat.Data.ReviewPostRight.Validation
  alias Chat.Data.Schemas.ReviewPostRight
  alias Chat.Data.Types.ReviewPostRightSignHash
  alias EnigmaPq

  use Chat.Data.Shapes.Shape,
    persist: [
      upsert: &PostRightData.upsert_post_right/1,
      get: &PostRightData.get_post_right/1,
      lookup_key: :review_hash,
      validate_insert: &Validation.validate_post_right_insert/1,
      validate_update: &Validation.validate_post_right_update/2
    ]

  use Toolbox.OriginLog

  @impl true
  def shape_name, do: :review_post_right

  @impl true
  def schema_module, do: ReviewPostRight

  @impl true
  def sync_required_parents(_op, %{author_hash: ah}) do
    [{:user_card, ah}]
  end

  @impl true
  def sync_derive_fields(%ReviewPostRight{sign_b64: sign_b64} = right)
      when is_binary(sign_b64) do
    sign_hash =
      sign_b64
      |> EnigmaPq.hash()
      |> ReviewPostRightSignHash.from_binary()

    %{right | sign_hash: sign_hash}
  end

  def sync_derive_fields(right), do: right
end
