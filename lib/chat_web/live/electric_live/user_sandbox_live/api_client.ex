defmodule ChatWeb.ElectricLive.UserSandboxLive.ApiClient do
  @moduledoc """
  API client for Electric ingest operations with request/response logging.

  Facade over `ApiClient.Users` (user card writes) and `ApiClient.Storage`
  (user storage reads and writes).
  """

  alias ChatWeb.ElectricLive.UserSandboxLive.ApiClient.Storage
  alias ChatWeb.ElectricLive.UserSandboxLive.ApiClient.Users

  defdelegate create_user(name, base_url), to: Users
  defdelegate update_user_name(existing_card, sign_skey, new_name, base_url), to: Users
  defdelegate delete_user(user_hash, sign_skey, base_url), to: Users
  defdelegate ingest_imported_user(user_data, base_url), to: Users

  defdelegate create_storage(user_hash, sign_skey, uuid, value_binary, base_url), to: Storage
  defdelegate update_storage(user_hash, sign_skey, uuid, value_binary, base_url), to: Storage
  defdelegate delete_storage(user_hash, sign_skey, uuid, base_url), to: Storage
  defdelegate fetch_user_storage(user_hash, sign_skey, base_url), to: Storage
end
