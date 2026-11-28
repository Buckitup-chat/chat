defmodule Chat.Test.UserStorageIngestFixtures do
  @moduledoc "Signed `user_storage` ingest payloads for the Electric ingest controller tests."

  import Chat.Test.ElectricIngestHelpers, only: [signature_and_hash: 3, to_base64: 1]

  alias Chat.Data.Schemas.UserStorage
  alias Chat.Data.Types.UserStorageSignHash

  @doc """
  Ingest payload with a single signed `user_storage` insert.
  `owner_timestamp` defaults to now.
  """
  def user_storage_insert_payload(
        user_hash,
        uuid,
        value,
        sign_skey,
        owner_timestamp \\ System.system_time(:second)
      ) do
    {sign_b64, sign_hash} = sign_storage(user_hash, uuid, value, owner_timestamp, sign_skey)

    single_mutation(%{
      "type" => "insert",
      "modified" => %{
        "user_hash" => user_hash,
        "uuid" => uuid,
        "value_b64" => to_base64(value),
        "deleted_flag" => false,
        "owner_timestamp" => owner_timestamp,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      }
    })
  end

  @doc "Ingest payload with a single signed `user_storage` update, one second newer than now."
  def user_storage_update_payload(user_hash, uuid, new_value, sign_skey) do
    owner_timestamp = System.system_time(:second) + 1

    {sign_b64, sign_hash} = sign_storage(user_hash, uuid, new_value, owner_timestamp, sign_skey)

    single_mutation(%{
      "type" => "update",
      "original" => %{"user_hash" => user_hash, "uuid" => uuid},
      "changes" => %{
        "value_b64" => to_base64(new_value),
        "owner_timestamp" => owner_timestamp,
        "sign_b64" => to_base64(sign_b64),
        "sign_hash" => sign_hash
      }
    })
  end

  @doc "Ingest payload with a single `user_storage` delete."
  def user_storage_delete_payload(user_hash, uuid) do
    single_mutation(%{
      "type" => "delete",
      "original" => %{"user_hash" => user_hash, "uuid" => uuid}
    })
  end

  defp single_mutation(mutation) do
    %{
      "mutations" => [
        Map.put(mutation, "syncMetadata", %{"relation" => "user_storage"})
      ]
    }
  end

  defp sign_storage(user_hash, uuid, value, owner_timestamp, sign_skey) do
    %UserStorage{
      user_hash: user_hash,
      uuid: uuid,
      value_b64: value,
      deleted_flag: false,
      parent_sign_hash: nil,
      owner_timestamp: owner_timestamp
    }
    |> signature_and_hash(sign_skey, &UserStorageSignHash.from_binary/1)
  end
end
