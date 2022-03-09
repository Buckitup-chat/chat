defmodule Chat.Dialogs.Registry do
  @moduledoc "Holds all dialogs"

  alias Chat.Db
  alias Chat.Dialogs
  alias Chat.User
  alias Chat.Utils

  def update(%Dialogs.Dialog{} = dialog) do
    Db.db()
    |> CubDB.put({:dialogs, dialog |> dialog_key()}, dialog)
  end

  def find(%Chat.Identity{} = me, %Chat.Card{} = peer) do
    Db.db()
    |> CubDB.get({:dialogs, peer_key(me, peer)})
  end

  defp peer_key(%Chat.Identity{} = me, %Chat.Card{} = peer) do
    [me, peer]
    |> Enum.map(&User.pub_key/1)
    |> key()
  end

  defp dialog_key(%Dialogs.Dialog{a_key: a_key, b_key: b_key}) do
    [a_key, b_key]
    |> key()
  end

  defp key(peer_keys) do
    peer_keys
    |> Enum.map(&Utils.hash/1)
    |> Enum.sort()
    |> Enum.join()
  end
end
