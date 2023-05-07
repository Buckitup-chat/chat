defmodule ChatWeb.MainLive.Page.RecoverKeyShareTest do
  @moduledoc false
  use ChatWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Chat.KeyShare, only: [generate_key_shares: 1]

  alias Chat.{Card, User}

  alias ChatWeb.MainLive.Page.RecoverKeyShare

  setup do
    me = "User" |> User.login()
    {:ok, me: me}
  end

  describe "user recover the key" do
    test "render component", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "restoreAuth")

      socket =
        view.pid
        |> :sys.get_state()
        |> Map.get(:socket)

      assert render_component(RecoverKeyShare,
               id: "recover-share-key",
               uploads: socket.assigns.uploads,
               step: :initial
             ) =~ "Upload Key Files"
    end

    test "mount", %{conn: conn} do
      view = conn |> render_form() |> Map.get(:view)

      {:ok, socket} =
        view.pid
        |> :sys.get_state()
        |> Map.get(:socket)
        |> RecoverKeyShare.mount()

      assert socket.assigns.user_recovery_hash == nil
      assert socket.assigns.shares == []
    end

    test "handle upload", %{conn: conn, me: me} do
      {time = System.os_time(),
       name = "This is my ID #{me.name}-#{Enigma.short_hash(me.public_key)}.social_part"}

      view = conn |> render_form() |> Map.get(:view)

      social_part = me |> key_parts(:keys) |> List.first()

      entry = [
        %{
          last_modified: time,
          name: name,
          content: social_part,
          size: byte_size(social_part),
          type: "text/plain"
        }
      ]

      file =
        view
        |> file_input("#recover-keys-form", :recovery_keys, entry)

      file |> render_upload(name)

      socket = view.pid |> :sys.get_state() |> Map.get(:socket)

      assert {:noreply, socket} = RecoverKeyShare.handle_progress(:recovery_keys, entry, socket)
    end
  end

  defp render_form(conn) do
    {:ok, view, _html} = live(conn, "/")

    render_hook(view, "restoreAuth")

    html =
      view
      |> element("#recoverKeyButton")
      |> render_click()

    %{html: html, view: view}
  end

  defp key_parts(user, option \\ :all) do
    shares =
      {user,
       ["Kevin", "John", "Mike", "Liza"]
       |> Enum.map(fn name ->
         name |> User.login() |> Card.from_identity()
       end)}
      |> generate_key_shares()

    case option do
      :all -> shares
      :keys -> shares |> Enum.map(& &1.key)
    end
  end
end
