defmodule Chat.Dialogs.Registry do
  @moduledoc "Holds all dialogs"

  alias Chat.Db
  alias Chat.Dialogs.Dialog

  def update(%Dialog{} = dialog) do
    Db.put({:dialogs, dialog |> Enigma.hash()}, dialog)
  end

  def find(me, peer) do
    Db.get({:dialogs, Dialog.start(me, peer) |> Enigma.hash()})
  end
end
