defmodule Chat.Data.User.Validation do
  alias Chat.Data.Schemas.UserCard
  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.User, as: UserData
  alias EnigmaPq
  alias Phoenix.Sync.Writer.Operation

  def user_card_allowed(operation, %{challenge: challenge, signature: signature}) do
    sign_pkey =
      case operation do
        %Operation{operation: :insert} ->
          {:ok, sign_pkey} = operation_change(operation, "sign_pkey")
          sign_pkey

        %Operation{operation: :update, data: data} ->
          data["user_hash"]
          |> UserData.get_card()
          |> then(fn card -> card.sign_pkey end)

        %Operation{operation: :delete, data: data} ->
          data["user_hash"]
          |> UserData.get_card()
          |> then(fn card -> card.sign_pkey end)
      end

    true = EnigmaPq.verify(challenge, signature, sign_pkey)
    :ok
  rescue
    _ -> {:error, "Invalid operation"}
  end

  def user_card_validate(card, changes, op) do
    case op do
      :insert -> card |> UserCard.create_changeset(changes) |> fail_invalid_user_card()
      :update -> card |> UserCard.update_name_changeset(changes)
      :delete -> card
    end
  end

  defp fail_invalid_user_card(changeset) do
    with true <- changeset.valid?,
         card_data <- Ecto.Changeset.apply_changes(changeset),
         false <- UserData.valid_card?(card_data) do
      Ecto.Changeset.add_error(changeset, :user_hash, "invalid_user_card_integrity")
    else
      _ -> changeset
    end
  end

  def user_card_validate(card, changes, :insert) do
    changeset = UserCard.create_changeset(card, changes)

    with true <- changeset.valid?,
         card_data <- Ecto.Changeset.apply_changes(changeset),
         false <- UserData.valid_card?(card_data) do
      Ecto.Changeset.add_error(changeset, :user_hash, "invalid_user_card_integrity")
    else
      _ -> changeset
    end
  end

  def user_card_validate(card, changes, :update) do
    UserCard.update_name_changeset(card, changes)
  end

  def user_card_validate(card, _changes, :delete) do
    card
  end

  def user_storage_allowed(operation, %{challenge: challenge, signature: signature}) do
    user_hash =
      case operation do
        %Operation{operation: :insert, changes: changes} ->
          changes["user_hash"] || changes[:user_hash]

        %Operation{operation: :update, data: %{"user_hash" => hash}} ->
          hash

        %Operation{operation: :delete, data: %{"user_hash" => hash}} ->
          hash
      end

    card = UserData.get_card(user_hash)
    true = EnigmaPq.verify(challenge, signature, card.sign_pkey)
    :ok
  rescue
    _ -> {:error, "Invalid operation"}
  end

  def user_storage_validate(storage, changes, op) do
    case op do
      :insert -> storage |> UserStorage.create_changeset(changes)
      :update -> storage |> UserStorage.update_changeset(changes)
      :delete -> storage
    end
  end

  defp operation_change(%Operation{changes: changes}, field) do
    case Map.get(changes, field) || Map.get(changes, String.to_existing_atom(field)) do
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, "Missing #{field} in mutation changes"}
    end
  end
end
