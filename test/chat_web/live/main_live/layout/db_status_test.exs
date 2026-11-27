defmodule ChatWeb.MainLive.Layout.DbStatusTest do
  use ChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ChatWeb.MainLive.Layout.DbStatus

  @mode_icons [
    internal: "crossedDataBase",
    main: "dataBase",
    internal_to_main: "dataBase",
    main_to_internal: "crossedDataBase"
  ]

  @red_icon ~r/class="[^"]*fill-red-600/

  @flag_icons [backup: "backUp", replication: "replication", cargo: "cargo"]

  for layout <- [:desktop, :mobile] do
    describe "#{layout}/1" do
      test "shows the icon of each mode, red when read only" do
        for {mode, icon} <- @mode_icons do
          html = render_status(unquote(layout), status(mode, :no))

          assert html =~ ~s(href="/images/icons/#{icon}.svg##{icon}")
          assert html =~ @red_icon
        end
      end

      test "pulses while switching" do
        assert render_status(unquote(layout), status(:main_to_internal)) =~ "animate-pulse"
        refute render_status(unquote(layout), status(:main)) =~ "animate-pulse"
      end

      test "shows flag icons" do
        for {flag, icon} <- @flag_icons do
          html = render_status(unquote(layout), status(:main, :yes, [{flag, true}]))

          assert html =~ ~s(href="/images/icons/#{icon}.svg##{icon}")
          refute html =~ @red_icon
        end
      end

      test "shows usb dump progress" do
        status = status(:main, :yes, usb_drive_dump: true)

        assert render_status(unquote(layout), status, %{progress: %{percentage: 50}}) =~
                 ~S(stroke-dashoffset="63.0")

        assert render_status(unquote(layout), status, %{}) =~ ~S(stroke-dashoffset="126.0")
      end
    end
  end

  # Helpers

  defp render_status(layout, status, dump_room \\ nil),
    do:
      render_component(&apply(DbStatus, layout, [&1]),
        status: status,
        usb_drive_dump_room: dump_room
      )

  defp status(mode, writable \\ :yes, flags \\ []),
    do: %{mode: mode, writable: writable, flags: flags}
end
