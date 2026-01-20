defmodule NaiveApi.ChatTest do
  use ExUnit.Case
  alias Chat.Card
  alias Chat.Db.ChangeTracker
  alias Chat.Dialogs
  alias Chat.FileIndex
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.User
  alias NaiveApi.Types.Bitstring
  alias Support.FakeData

  @schema NaiveApi.Schema

  describe "query: chatRead" do
    @text "¡Hola!"
    @image_name "Corazón.jpeg"
    @room_name "Escuela de amor"
    @read_query """
      query ChatRead($peerPublicKey: PublicKey!, $myKeypair: InputKeyPair!) { 
        chatRead(peerPublicKey: $peerPublicKey, myKeypair: $myKeypair) {
          id
          index
          timestamp
          author {
            publicKey
          }
          content {
            __typename
            ... on FileContent {
              url
              type
              sizeBytes
              initialName
            }
            ... on TextContent {
             text
            }
            ... on RoomInviteContent {
              keys {
                public_key
                private_key
              }
            }
          }
        }
      }
    """
    setup do
      me = User.login("Pedro") |> tap(&User.register/1)
      peer = User.login("Diego") |> tap(&User.register/1)
      dialog = Dialogs.find_or_open(me, Card.from_identity(peer))
      {room_identity, _my_room} = Rooms.add(me, @room_name)

      %Messages.Text{text: @text, timestamp: now()}
      |> Dialogs.add_new_message(me, dialog)

      FakeData.image(@image_name)
      |> Dialogs.add_new_message(me, dialog)

      room_identity
      |> Messages.RoomInvite.new()
      |> Dialogs.add_new_message(me, dialog)

      [me: me, peer: peer]
    end

    test "returns messages of different formats", %{me: me, peer: peer} do
      {:ok, %{data: %{"chatRead" => [text, image, room_invite]}}} =
        Absinthe.run(@read_query, @schema,
          variables: %{
            "peerPublicKey" => Bitstring.serialize_33(peer.public_key),
            "myKeypair" => %{
              "privateKey" => Bitstring.serialize_32(me.private_key),
              "publicKey" => Bitstring.serialize_33(me.public_key)
            }
          }
        )

      assert %{"__typename" => "TextContent", "text" => "¡Hola!"} == text["content"]

      assert match?(
               %{
                 "__typename" => "FileContent",
                 "initialName" => @image_name,
                 "sizeBytes" => _,
                 "type" => "IMAGE",
                 "url" => "/get/image/" <> _
               },
               image["content"]
             )

      assert match?(
               %{
                 "__typename" => "RoomInviteContent",
                 "keys" => %{"public_key" => _, "private_key" => _}
               },
               room_invite["content"]
             )
    end
  end

  describe "mutation: chatSendText" do
    @text "¡Hola!"
    @send_text_mutation """
      mutation ChatSendText($peerPublicKey: PublicKey!, $myKeypair: InputKeyPair!, $text: String!, $timestamp: Int!) { 
        chatSendText(peerPublicKey: $peerPublicKey, myKeypair: $myKeypair, text: $text, timestamp: $timestamp) {
          id
          index
        }
      }
    """
    setup do
      me = User.login("Pedro") |> tap(&User.register/1)
      peer = User.login("Diego") |> tap(&User.register/1)
      dialog = Dialogs.find_or_open(me, Card.from_identity(peer))
      [me: me, peer: peer, dialog: dialog]
    end

    test "sends text", %{me: me, peer: peer, dialog: dialog} do
      {:ok, %{data: %{"chatSendText" => message_reference}}} =
        Absinthe.run(@send_text_mutation, @schema,
          variables: %{
            "peerPublicKey" => Bitstring.serialize_33(peer.public_key),
            "myKeypair" => %{
              "public_key" => Bitstring.serialize_33(me.public_key),
              "private_key" => Bitstring.serialize_32(me.private_key)
            },
            "text" => @text,
            "timestamp" => now()
          }
        )

      assert 1 == message_reference["index"]

      assert match?(
               {:ok, [uuid: _, binary: _, type: _, version: _, variant: _]},
               UUID.info(message_reference["id"])
             )
    end
  end

  describe "mutation: chatSendFile" do
    @upload_key_mutation """
    mutation createUpload($myKeypair: InputKeyPair!, $destination: InputUploadDestination!, $entry: InputUploadEntry!) {
      uploadKey(myKeypair: $myKeypair, destination: $destination, entry: $entry)
    }
    """

    @send_file_mutation """
    mutation chatSendFile($peerPublicKey: PublicKey!, $myKeypair: InputKeyPair!, $uploadKey: FileKey!) {
      chatSendFile(peerPublicKey: $peerPublicKey, myKeypair: $myKeypair, uploadKey: $uploadKey) {
        id
        index
      }
    }
    """

    @chat_read_query """
    query ChatRead($peerPublicKey: PublicKey!, $myKeypair: InputKeyPair!) {
      chatRead(peerPublicKey: $peerPublicKey, myKeypair: $myKeypair) {
        content {
          __typename
          ... on FileContent {
            initialName
            sizeBytes
            type
          }
        }
      }
    }
    """

    setup do
      me = User.login("Pedro") |> tap(&User.register/1)
      peer = User.login("Diego") |> tap(&User.register/1)
      dialog = Dialogs.find_or_open(me, Card.from_identity(peer))

      ChangeTracker.await()

      # Create upload key with DIALOG destination
      {:ok, %{data: %{"uploadKey" => upload_key}}} =
        Absinthe.run(@upload_key_mutation, @schema,
          variables: %{
            "destination" => %{
              "type" => "DIALOG",
              "keypair" => %{
                "publicKey" => Bitstring.serialize_33(peer.public_key),
                "privateKey" => Bitstring.serialize_32(me.private_key)
              }
            },
            "myKeypair" => %{
              "publicKey" => Bitstring.serialize_33(me.public_key),
              "privateKey" => Bitstring.serialize_32(me.private_key)
            },
            "entry" => %{
              "clientName" => "vacation.jpeg",
              "clientType" => "image/jpeg",
              "clientSize" => 102_400,
              "clientRelativePath" => "/Downloads/vacation.jpeg",
              "clientLastModified" => 1_679_466_076
            }
          }
        )

      [me: me, peer: peer, dialog: dialog, upload_key: upload_key]
    end

    test "returns created message reference", %{
      me: me,
      peer: peer,
      upload_key: upload_key
    } do
      {:ok, %{data: %{"chatSendFile" => message_reference}}} =
        Absinthe.run(@send_file_mutation, @schema,
          variables: %{
            "peerPublicKey" => Bitstring.serialize_33(peer.public_key),
            "myKeypair" => %{
              "publicKey" => Bitstring.serialize_33(me.public_key),
              "privateKey" => Bitstring.serialize_32(me.private_key)
            },
            "uploadKey" => upload_key
          }
        )

      assert 1 == message_reference["index"]

      assert match?(
               {:ok, [uuid: _, binary: _, type: _, version: _, variant: _]},
               UUID.info(message_reference["id"])
             )
    end

    test "saves file secrets for both dialog participants", %{
      me: me,
      peer: peer,
      dialog: dialog,
      upload_key: upload_key
    } do
      {:ok, %{data: %{"chatSendFile" => %{"id" => _msg_id}}}} =
        Absinthe.run(@send_file_mutation, @schema,
          variables: %{
            "peerPublicKey" => Bitstring.serialize_33(peer.public_key),
            "myKeypair" => %{
              "publicKey" => Bitstring.serialize_33(me.public_key),
              "privateKey" => Bitstring.serialize_32(me.private_key)
            },
            "uploadKey" => upload_key
          }
        )

      # Wait for database writes to complete
      ChangeTracker.await()

      # Decode upload_key from hex string to binary for FileIndex lookup
      {:ok, upload_key_binary} = Base.decode16(upload_key, case: :lower)

      # Verify secrets are saved for both participants
      secret_a = FileIndex.get(dialog.a_key, upload_key_binary)
      secret_b = FileIndex.get(dialog.b_key, upload_key_binary)

      assert secret_a != nil
      assert secret_b != nil
    end

    test "fails with wrong upload key", %{me: me, peer: peer} do
      fake_upload_key = :crypto.strong_rand_bytes(32)

      {:ok, %{errors: [%{message: error_message}]}} =
        Absinthe.run(@send_file_mutation, @schema,
          variables: %{
            "peerPublicKey" => Bitstring.serialize_33(peer.public_key),
            "myKeypair" => %{
              "publicKey" => Bitstring.serialize_33(me.public_key),
              "privateKey" => Bitstring.serialize_32(me.private_key)
            },
            "uploadKey" => Bitstring.serialize_32(fake_upload_key)
          }
        )

      assert "Wrong upload key" == error_message
    end

    test "file message can be read from dialog", %{
      me: me,
      peer: peer,
      upload_key: upload_key
    } do
      # Send file
      Absinthe.run(@send_file_mutation, @schema,
        variables: %{
          "peerPublicKey" => Bitstring.serialize_33(peer.public_key),
          "myKeypair" => %{
            "publicKey" => Bitstring.serialize_33(me.public_key),
            "privateKey" => Bitstring.serialize_32(me.private_key)
          },
          "uploadKey" => upload_key
        }
      )

      # Read it back
      {:ok, %{data: %{"chatRead" => [file_message]}}} =
        Absinthe.run(@chat_read_query, @schema,
          variables: %{
            "peerPublicKey" => Bitstring.serialize_33(peer.public_key),
            "myKeypair" => %{
              "publicKey" => Bitstring.serialize_33(me.public_key),
              "privateKey" => Bitstring.serialize_32(me.private_key)
            }
          }
        )

      assert %{
               "__typename" => "FileContent",
               "initialName" => "vacation.jpeg",
               "sizeBytes" => 102_400,
               "type" => "IMAGE"
             } = file_message["content"]
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_unix()
end
