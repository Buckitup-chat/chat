defmodule NaiveApi.Upload do
  @moduledoc "Upload resolvers"
  use NaiveApi, :resolver

  alias Chat.Db.ChangeTracker
  alias Chat.{ChunkedFiles, ChunkedFilesMultisecret}
  alias Chat.Identity
  alias Chat.Upload.{Upload, UploadIndex, UploadKey}

  def create_key(_, %{my_keypair: my_keypair, destination: destination, entry: entry}, _) do
    upload_key =
      destination
      |> serialize_destination()
      |> UploadKey.new(my_keypair.public_key, entry)

    encrypted_secret =
      upload_key
      |> ChunkedFiles.new_upload()
      |> ChunkedFiles.encrypt_secret(Identity.from_keys(my_keypair))

    UploadIndex.add(upload_key, %Upload{
      encrypted_secret: encrypted_secret,
      timestamp: DateTime.utc_now() |> DateTime.to_unix(),
      client_size: entry.client_size,
      client_type: entry.client_type,
      client_name: entry.client_name
    })

    initial_secret = ChunkedFiles.get_file(upload_key)
    ChunkedFilesMultisecret.generate(upload_key, entry.client_size, initial_secret)

    ChangeTracker.await()

    upload_key
    |> ok()
  end

  defp serialize_destination(
         %{keypair: %{public_key: public_key, private_key: private_key}} = destination
       ) do
    Map.put(destination, :keypair, %{
      public_key: public_key |> Base.encode16(case: :lower),
      private_key: private_key |> Base.encode16(case: :lower)
    })
  end
end
