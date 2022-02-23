defmodule Chat.Dialogs.Registry do
  @moduledoc "Holds all dialogs"
  use GenServer

  alias Chat.Dialogs
  alias Chat.User

  ### Interface

  def find(%Chat.Identity{} = me, %Chat.Card{} = peer),
    do: GenServer.call(__MODULE__, {:find, me, peer})

  def update(%Dialogs.Dialog{} = dialog), do: GenServer.cast(__MODULE__, {:update, dialog})

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  ### Implementation

  @impl true
  def init(_) do
    {:ok, %{list: %{}}}
  end

  @impl true
  def handle_call({:find, me, peer}, _, %{list: list} = state) do
    dialog = Map.get(list, peer_key(me, peer))
    {:reply, dialog, state}
  end

  @impl true
  def handle_cast({:update, dialog}, %{list: list} = state) do
    new_list = Map.put(list, dialog_key(dialog), dialog)

    {:noreply, %{state | list: new_list}}
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

  defp key(peer_keys), do: Enum.sort(peer_keys)
end
