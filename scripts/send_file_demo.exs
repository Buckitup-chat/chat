#!/usr/bin/env elixir

Mix.install([
  {:req, "~> 0.5"},
  {:curvy, "~> 0.3"}
])

defmodule SendFileDemo do
  @moduledoc """
  Demonstrates the complete GraphQL API flow for:
  1. Creating 2 users
  2. Generating a test file
  3. Uploading and sending the file to their dialog

  Usage: elixir scripts/send_file_demo.exs
  """

  @api_base "http://localhost:4444"
  @graphql_endpoint "#{@api_base}/naive_api"
  @chunk_size 10_485_760  # 10MB
  @file_size 1_048_576    # 1MB test file

  # GraphQL Mutations
  @user_signup_mutation """
  mutation UserSignUp($name: String!, $keypair: InputKeyPair) {
    userSignUp(name: $name, keypair: $keypair) {
      name
      keys {
        publicKey
        privateKey
      }
    }
  }
  """

  @upload_key_mutation """
  mutation UploadKey(
    $myKeypair: InputKeyPair!,
    $destination: InputUploadDestination!,
    $entry: InputUploadEntry!
  ) {
    uploadKey(
      myKeypair: $myKeypair,
      destination: $destination,
      entry: $entry
    )
  }
  """

  @send_file_mutation """
  mutation ChatSendFile(
    $peerPublicKey: PublicKey!,
    $myKeypair: InputKeyPair!,
    $uploadKey: FileKey!
  ) {
    chatSendFile(
      peerPublicKey: $peerPublicKey,
      myKeypair: $myKeypair,
      uploadKey: $uploadKey
    ) {
      id
      index
    }
  }
  """

  def run do
    IO.puts("\n=== BuckitUp GraphQL File Upload Demo ===\n")

    # Step 1: Create two users
    IO.puts("Creating users...")
    alice = create_user("Alice")
    bob = create_user("Bob")
    IO.puts("✓ User created: #{alice.name} (public_key: #{String.slice(alice.public_key, 0..9)}...)")
    IO.puts("✓ User created: #{bob.name} (public_key: #{String.slice(bob.public_key, 0..9)}...)\n")

    # Step 2: Create temporary test file
    IO.puts("Creating temporary test file (#{format_bytes(@file_size)})...")
    file_path = create_test_file()
    IO.puts("✓ File created: #{file_path}\n")

    # Step 3: Create upload key
    IO.puts("Creating upload key...")
    upload_key = create_upload_key(alice, bob, file_path)
    IO.puts("✓ Upload key: #{String.slice(upload_key, 0..15)}...\n")

    # Step 4: Upload file chunks
    IO.puts("Uploading file chunks...")
    upload_chunks(file_path, upload_key)
    IO.puts("✓ All chunks uploaded\n")

    # Step 5: Send file message
    IO.puts("Sending file message...")
    message_ref = send_file_message(alice, bob, upload_key)
    IO.puts("✓ Message sent! ID: #{message_ref["id"]}, Index: #{message_ref["index"]}\n")

    # Cleanup
    File.rm(file_path)

    IO.puts("Done! File successfully sent from #{alice.name} to #{bob.name}.")
  end

  # User Creation

  defp create_user(name) do
    {public_key, private_key} = generate_keypair()

    variables = %{
      "name" => name,
      "keypair" => %{
        "publicKey" => serialize_key_33(public_key),
        "privateKey" => serialize_key_32(private_key)
      }
    }

    response = graphql_request(@user_signup_mutation, variables)

    %{
      name: response["userSignUp"]["name"],
      public_key: serialize_key_33(public_key),
      private_key: serialize_key_32(private_key),
      public_key_binary: public_key,
      private_key_binary: private_key
    }
  end

  # File Creation

  defp create_test_file do
    timestamp = System.system_time(:second)
    file_path = "/tmp/test_file_#{timestamp}.bin"

    # Generate random bytes
    random_data = :crypto.strong_rand_bytes(@file_size)
    File.write!(file_path, random_data)

    file_path
  end

  # Upload Key Creation

  defp create_upload_key(sender, receiver, file_path) do
    variables = %{
      "myKeypair" => %{
        "publicKey" => sender.public_key,
        "privateKey" => sender.private_key
      },
      "destination" => %{
        "type" => "DIALOG",
        "keypair" => %{
          "publicKey" => receiver.public_key,
          "privateKey" => sender.private_key
        }
      },
      "entry" => %{
        "clientName" => Path.basename(file_path),
        "clientType" => "application/octet-stream",
        "clientSize" => @file_size,
        "clientRelativePath" => file_path,
        "clientLastModified" => System.system_time(:second)
      }
    }

    response = graphql_request(@upload_key_mutation, variables)
    response["uploadKey"]
  end

  # Chunk Upload

  defp upload_chunks(file_path, upload_key) do
    file_size = File.stat!(file_path).size

    file_path
    |> File.stream!([], @chunk_size)
    |> Stream.with_index()
    |> Enum.each(fn {chunk, index} ->
      offset = index * @chunk_size
      chunk_size = byte_size(chunk)
      range_end = offset + chunk_size - 1

      upload_chunk(upload_key, chunk, offset, range_end, file_size)
      IO.puts("  ✓ Chunk #{index + 1} uploaded (#{format_bytes(chunk_size)})")
    end)
  end

  defp upload_chunk(upload_key, chunk, range_start, range_end, total_size) do
    url = "#{@api_base}/upload_chunk/#{upload_key}"

    response = Req.put!(url,
      body: chunk,
      headers: [
        {"content-type", "application/octet-stream"},
        {"content-range", "bytes #{range_start}-#{range_end}/#{total_size}"},
        {"content-length", "#{byte_size(chunk)}"}
      ]
    )

    if response.status != 200 do
      raise "Chunk upload failed with status #{response.status}"
    end
  end

  # Send File Message

  defp send_file_message(sender, receiver, upload_key) do
    variables = %{
      "peerPublicKey" => receiver.public_key,
      "myKeypair" => %{
        "publicKey" => sender.public_key,
        "privateKey" => sender.private_key
      },
      "uploadKey" => upload_key
    }

    response = graphql_request(@send_file_mutation, variables)
    response["chatSendFile"]
  end

  # GraphQL Helper

  defp graphql_request(query, variables) do
    response = Req.post!(@graphql_endpoint,
      json: %{
        query: query,
        variables: variables
      }
    )

    if response.status != 200 do
      raise "GraphQL request failed with status #{response.status}"
    end

    body = response.body

    if Map.has_key?(body, "errors") do
      errors = body["errors"]
      raise "GraphQL errors: #{inspect(errors)}"
    end

    body["data"]
  end

  # Crypto Helpers

  defp generate_keypair do
    key = Curvy.generate_key()
    private = Curvy.Key.to_privkey(key)
    public = Curvy.Key.to_pubkey(key)
    {public, private}
  end

  defp serialize_key_32(<<raw::binary-size(32)>>) do
    Base.encode16(raw, case: :lower)
  end

  defp serialize_key_33(<<raw::binary-size(33)>>) do
    Base.encode16(raw, case: :lower)
  end

  # Formatting Helpers

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 2)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 2)} MB"
end

# Run the demo
SendFileDemo.run()
