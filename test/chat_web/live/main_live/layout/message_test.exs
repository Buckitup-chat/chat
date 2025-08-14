defmodule ChatWeb.MainLive.Layout.MessageTest do
  use ChatWeb.ConnCase, async: true

  import ChatWeb.LiveTestHelpers
  import Phoenix.LiveViewTest

  alias Chat.Dialogs.PrivateMessage
  alias ChatWeb.MainLive.Layout.Message

  describe "text/1" do
    test "renders text of a message" do
      msg = %PrivateMessage{content: "message text", type: :text}

      view = render_component(&Message.text/1, msg: msg)
      assert has_vue_content?(view, "LinkedText", "message text")
    end
  end
end
