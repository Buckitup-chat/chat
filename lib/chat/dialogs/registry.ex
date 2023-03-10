defmodule Chat.Dialogs.Registry do
  @moduledoc "Holds all dialogs"

  alias Chat.Card
  alias Chat.Db
  alias Chat.Dialogs.Dialog
  alias Chat.Identity

  def update(%Dialog{} = dialog) do
    Db.put({:dialogs, dialog |> Enigma.hash()}, dialog)
  end

  def find(%Identity{} = me, %Card{} = peer) do
    Db.get({:dialogs, Dialog.start(me, peer) |> Enigma.hash()})
  end
end
