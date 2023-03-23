defmodule NaiveApi.RoomTest do
  use ExUnit.Case
  alias Chat.Db.ChangeTracker
  alias Chat.Messages
  alias Chat.Rooms
  alias Chat.User
  alias NaiveApi.Types.Bitstring
  alias Support.FakeData

  @schema NaiveApi.Schema

  describe "query: roomRead" do
    @text "¡Hola!"
    @image_name "Corazón.jpeg"
    @room_name "Escuela de amor"
    @read_query """
      query RoomRead($roomKeypair: InputKeyPair!) { 
        roomRead(roomKeypair: $roomKeypair) {
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
          }
        }
      }
    """
    setup do
      me = User.login("Pedro") |> tap(&User.register/1)
      {room_identity, _room} = Rooms.add(me, @room_name)

      %Messages.Text{text: @text, timestamp: now()}
      |> Rooms.add_new_message(me, room_identity.public_key)

      FakeData.image(@image_name)
      |> Rooms.add_new_message(me, room_identity.public_key)

      [me: me, room_identity: room_identity]
    end

    test "returns messages of different formats", %{room_identity: room_identity} do
      {:ok, %{data: %{"roomRead" => [text, image]}}} =
        Absinthe.run(@read_query, @schema,
          variables: %{
            "roomKeypair" => %{
              "public_key" => Bitstring.serialize_33(room_identity.public_key),
              "private_key" => Bitstring.serialize_32(room_identity.private_key)
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
    end

    defp now, do: DateTime.utc_now() |> DateTime.to_unix()
  end

  describe "mutation: roomSendText" do
    @mutation """
    mutation roomWrite($roomKeypair: InputKeyPair!, $myKeypair: InputKeyPair!, $text: String!) {
      roomSendText(roomKeypair: $roomKeypair, myKeypair: $myKeypair, text: $text) {
        id
        index
      }
    }
    """
    setup do
      me = User.login("Pedro") |> tap(&User.register/1)
      {room_identity, _room} = Rooms.add(me, "Escuela de amor")

      ChangeTracker.await()

      [me: me, room_identity: room_identity]
    end

    test "returns created message reference", %{me: me, room_identity: room_identity} do
      {:ok, %{data: %{"roomSendText" => message_reference}}} =
        Absinthe.run(@mutation, @schema,
          variables: %{
            "roomKeypair" => %{
              "public_key" => Bitstring.serialize_33(room_identity.public_key),
              "private_key" => Bitstring.serialize_32(room_identity.private_key)
            },
            "myKeypair" => %{
              "public_key" => Bitstring.serialize_33(me.public_key),
              "private_key" => Bitstring.serialize_32(me.private_key)
            },
            "text" => "¡Hola!"
          }
        )

      assert 1 == message_reference["index"]

      assert match?(
               {:ok, [uuid: _, binary: _, type: _, version: _, variant: _]},
               UUID.info(message_reference["id"])
             )
    end

    test "can't write empty text", %{me: me, room_identity: room_identity} do
      {:ok, %{errors: [%{message: error_message}]}} =
        Absinthe.run(@mutation, @schema,
          variables: %{
            "roomKeypair" => %{
              "public_key" => Bitstring.serialize_33(room_identity.public_key),
              "private_key" => Bitstring.serialize_32(room_identity.private_key)
            },
            "myKeypair" => %{
              "public_key" => Bitstring.serialize_33(me.public_key),
              "private_key" => Bitstring.serialize_32(me.private_key)
            },
            "text" => ""
          }
        )

      assert "Can't write empty text" == error_message
    end
  end

  describe "mutation: roomSendFile" do
    @upload_key_mutation """
    mutation createUpload($myKeypair: InputKeyPair!, $destination: InputUploadDestination!, $entry: InputUploadEntry!) {
      uploadKey(myKeypair: $myKeypair, destination: $destination, entry: $entry)
    }
    """
    @send_file_mutation """
    mutation roomSendFile($roomKeypair: InputKeyPair!, $myKeypair: InputKeyPair!, $uploadKey: FileKey!) {
      roomSendFile(roomKeypair: $roomKeypair, myKeypair: $myKeypair, uploadKey: $uploadKey) {
        id
        index
      }
    }
    """
    setup do
      me = User.login("Pedro") |> tap(&User.register/1)
      {room_identity, _room} = Rooms.add(me, "Escuela de amor")

      {:ok, %{data: %{"uploadKey" => upload_key}}} =
        Absinthe.run(@upload_key_mutation, @schema,
          variables: %{
            "destination" => %{
              "type" => "ROOM",
              "keypair" => %{
                "public_key" => Bitstring.serialize_33(room_identity.public_key),
                "private_key" => Bitstring.serialize_32(room_identity.private_key)
              }
            },
            "myKeypair" => %{
              "public_key" => Bitstring.serialize_33(me.public_key),
              "private_key" => Bitstring.serialize_32(me.private_key)
            },
            "entry" => %{
              "clientName" => "1111111.jpeg",
              "clientType" => "image/jpeg",
              "clientSize" => 102_400,
              "clientRelativePath" => "/Downloads/1111111.jpeg",
              "clientLastModified" => 1_679_466_076
            }
          }
        )

      [me: me, room_identity: room_identity, upload_key: upload_key]
    end

    test "returns created message reference", %{
      me: me,
      room_identity: room_identity,
      upload_key: upload_key
    } do
      {:ok, %{data: %{"roomSendFile" => message_reference}}} =
        Absinthe.run(@send_file_mutation, @schema,
          variables: %{
            "roomKeypair" => %{
              "public_key" => Bitstring.serialize_33(room_identity.public_key),
              "private_key" => Bitstring.serialize_32(room_identity.private_key)
            },
            "myKeypair" => %{
              "public_key" => Bitstring.serialize_33(me.public_key),
              "private_key" => Bitstring.serialize_32(me.private_key)
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
  end
end
