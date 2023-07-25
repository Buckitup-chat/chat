defmodule ChatWeb.MainLive.Page.DialogTest do
  use ChatWeb.ConnCase, async: false

  import ChatWeb.LiveTestHelpers

  describe "chat links" do
    test "saves backup settings to the admin DB", %{conn: conn} do
      %{socket: %{assigns: %{my_id: hash}}} = login_by_key(%{conn: conn})

      %{socket: %{assigns: %{me: me, peer: peer, dialog: dialog}}} =
        login_by_key(%{conn: conn}, "/chat/#{Base.encode16(hash, case: :lower)}")

      assert Chat.Card.from_identity(me) == peer
      assert dialog != nil

      %{socket: %{assigns: %{peer: peer, dialog: dialog}}} =
        login_by_key(%{conn: conn}, "/chat/abc123")

      assert dialog == nil
      assert peer == nil
    end
  end
end
