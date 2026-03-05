defmodule ChatWeb.MainLive.Layout.PopupTest do
  use ChatWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias ChatWeb.MainLive.Layout.Popup

  test "renders popup #restrict-write-actions" do
    component = render_component(&Popup.restrict_write_actions/1, [])
    parsed = Floki.parse_document!(component)
    button = parsed |> Floki.find("button")

    assert parsed |> Floki.text() =~ "Read only mode"

    assert parsed |> Floki.text() =~
             "The device switched into read only mode. Storage drive needs to be upgraded."

    assert button |> Floki.text() =~ "Ok"
  end
end
