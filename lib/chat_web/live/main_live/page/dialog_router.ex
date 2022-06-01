defmodule ChatWeb.MainLive.Page.DialogRouter do
  @moduledoc "Route dialog events"

  alias ChatWeb.MainLive.Page

  #
  # LiveView events
  #

  def event(socket, event) do
    case event do
      {"accept-room-invite", %{"id" => id, "time" => time}} ->
        socket |> Page.Dialog.accept_room_invite({time |> String.to_integer(), id})
    end
  end

  #
  # Internal events
  #

  def info(socket, message) do
    # case message do
    #  {:new_message, glimpse} ->
    #    socket |> Page.Room.show_new(glimpse)
    # end
  end
end
