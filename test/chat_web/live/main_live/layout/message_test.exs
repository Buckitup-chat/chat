defmodule ChatWeb.MainLive.Layout.MessageTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.{Card, DryStorable, User}
  alias Chat.Content.{Files, RoomInvites}
  alias Chat.Dialogs.PrivateMessage
  alias Chat.Messages.RoomInvite
  alias Chat.Rooms.Room
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Layout.Message

  @file_types [audio: "a-audio", file: "Download", image: "chat-image-", video: "a-video"]

  describe "text/1" do
    test "renders text of a message" do
      msg = %PrivateMessage{content: "message text", type: :text}

      view = render_component(&Message.text/1, msg: msg)
      assert has_vue_content?(view, "LinkedText", "message text")
    end

    test "renders memo text" do
      view = render_component(&Message.text/1, msg: %{type: :memo, memo: "memo text"})
      assert has_vue_content?(view, "LinkedText", "memo text")
    end
  end

  describe "message_block/1 in a dialog" do
    setup do
      [me: User.login("Me"), peer: "Peer" |> User.login() |> Card.from_identity()]
    end

    test "renders every file type", ctx do
      for {type, marker} <- @file_types do
        html = render_dialog(ctx, file_msg(type))

        assert html =~ ~s(data-type="#{type}")
        assert html =~ marker
        assert html =~ "pic.png"
      end
    end

    test "renders broken file info", ctx do
      html = render_dialog(ctx, msg(:file, file_info: :broken, file_url: nil))

      assert html =~ "Broken file"
    end

    test "renders exported files with local paths", ctx do
      for {type, _} <- @file_types do
        html = render_dialog(ctx, exported_file_msg(type), export?: true)

        assert html =~ ~S(files/pic_)
        refute html =~ "selectCheckbox"
      end
    end

    test "renders memo messages", ctx do
      html = render_dialog(ctx, msg(:memo, memo: "long memo"))

      assert has_vue_content?(html, "LinkedText", "long memo")
    end

    test "renders room invites sent, received and self-copied", ctx do
      invite = invite_msg("Club")

      assert render_dialog(ctx, %{invite | is_mine?: true}) =~ "is invited by you into"
      assert render_dialog(ctx, %{invite | is_mine?: false}) =~ "wants you to join the room"

      self_copy = %{ctx | peer: Card.from_identity(ctx.me)}
      assert render_dialog(self_copy, %{invite | is_mine?: true}) =~ "You got the key copy"
    end

    test "renders nothing for a broken room invite", ctx do
      html = render_dialog(ctx, msg(:room_invite, content: "broken"))

      refute html =~ ~S(id="message-m1")
    end

    test "renders a placeholder for an unknown type", ctx do
      assert render_dialog(ctx, msg(:unknown)) =~ "error rendering message"
    end
  end

  describe "message_block/1 in a room" do
    test "renders an access request" do
      room_identity = User.login("Room")
      room = %Room{name: "Room", pub_key: room_identity.public_key, type: :private}
      author = User.login("Requester")
      msg = msg(:request, author_key: author.public_key)

      html =
        render_component(&Message.message_block/1,
          chat_type: :room,
          msg: msg,
          my_id: "other",
          room: room
        )

      assert html =~ "requested access to room"
    end
  end

  # Helpers

  defp render_dialog(%{me: me, peer: peer}, msg, opts \\ []) do
    render_component(&Message.message_block/1,
      chat_type: :dialog,
      export?: Keyword.get(opts, :export?, false),
      me: me,
      msg: msg,
      peer: peer
    )
  end

  defp msg(type, fields \\ []) do
    %{id: "m1", index: 1, is_mine?: false, timestamp: 0, type: type, content: nil}
    |> Map.merge(Map.new(fields))
  end

  defp file_msg(type),
    do: msg(type, file_info: ["k", "s", [], "image/png", "pic.png", "1 KB"], file_url: "/u/pic")

  defp exported_file_msg(type) do
    key = UUID.uuid4()
    secret = :crypto.strong_rand_bytes(32)
    {^key, _} = Files.add([key, Base.encode64(secret), [], "image/png", "pic.png", "1 KB"])
    wait_until(fn -> Files.get(key, secret) end)

    msg(type, content: StorageId.to_json({key, secret}))
  end

  defp invite_msg(room_name) do
    content = room_name |> User.login() |> RoomInvite.new() |> DryStorable.content()
    wait_until(fn -> content |> StorageId.from_json() |> RoomInvites.get() end)

    msg(:room_invite, content: content)
  end
end
