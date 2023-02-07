defmodule ChatWeb.MainLive.Layout.MessageTest do
  use ChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Chat.Dialogs.PrivateMessage
  alias ChatWeb.MainLive.Layout.Message

  describe "text/1" do
    test "renders text of a message" do
      msg = %PrivateMessage{content: "message text", type: :text}

      assert render_component(&Message.text/1, msg: msg) ==
               ~s(<div class="px-4 w-full">\n  <span class="flex-initial break-words">\n    message text\n  </span>\n</div>)
    end
  end
end
