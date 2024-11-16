defmodule NaiveApi.ChatTest do
  use ExUnit.Case
  alias Chat.Card
  alias Chat.Dialogs
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

    test "sends text", %{me: me, peer: peer} do
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

  defp now, do: DateTime.utc_now() |> DateTime.to_unix()
end
