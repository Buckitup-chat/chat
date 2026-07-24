defmodule Chat.Data.Shapes.ReviewRevokeRight do
  @moduledoc "Shape behaviour implementation for review_revoke_right."

  use Chat.Data.Shapes.Shape
  use Toolbox.OriginLog

  alias Chat.Data.ReviewRevokeRight, as: RevokeRightData
  alias Chat.Data.ReviewRevokeRight.Validation
  alias Chat.Data.Schemas.ReviewRevokeRight
  alias Chat.Data.Types.ReviewRevokeRightSignHash
  alias EnigmaPq

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

  @impl true
  def sync_persist(operation, right) do
    case operation do
      :insert ->
        right
        |> Validation.validate_revoke_right_insert()
        |> persist_insert(right)

      :update ->
        persist_update(right)
    end
  end

  defp persist_insert(changeset, right) do
    case changeset do
      %{valid?: true} ->
        RevokeRightData.upsert_revoke_right(changeset)

      %{valid?: false} = cs ->
        log("Invalid review_revoke_right insert: #{inspect(cs.errors)}", :warning)
        {:ok, right}
    end
  end

  defp persist_update(right) do
    case RevokeRightData.get_revoke_right(right.review_hash) do
      nil ->
        {:ok, right}

      existing ->
        existing
        |> Validation.validate_revoke_right_update(right)
        |> apply_changeset(right)
    end
  end

  defp apply_changeset(changeset, right) do
    case changeset do
      %{valid?: true} ->
        %ReviewRevokeRight{}
        |> ReviewRevokeRight.create_changeset(right |> Map.from_struct())
        |> RevokeRightData.upsert_revoke_right()

      %{valid?: false, action: :ignore} ->
        {:ok, right}

      %{valid?: false} = cs ->
        log("Invalid review_revoke_right update: #{inspect(cs.errors)}", :warning)
        {:ok, right}
    end
  end
end
