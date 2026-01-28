defmodule Chat.User.UsersBroker do
  @moduledoc "Keeps users"
  use GenServer
  import Tools.GenServerHelpers

  alias Chat.Card
  alias Chat.User

  def sync do
    GenServer.call(__MODULE__, :sync)
  end

  def list do
    GenServer.call(__MODULE__, :list)
  end

  def list(search_term) do
    GenServer.call(__MODULE__, {:list, search_term})
  end

  def put(%Card{} = card) do
    GenServer.cast(__MODULE__, {:put, card})
  end

  def put(%Chat.Identity{} = identity) do
    GenServer.cast(__MODULE__, {:put, Card.from_identity(identity)})
  end

  def forget(key) do
    GenServer.cast(__MODULE__, {:forget, key})
  end

  ## Defining GenServer Callbacks

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))

  def init(_) do
    Process.flag(:sensitive, true)

    %{} |> ok_continue(:sync)
  end

  def handle_continue(:sync, _) do
    User.list() |> noreply()
  catch
    _, _ -> noreply([])
  end

  def handle_call(:sync, _from, users) do
    User.list() |> reply(:ok)
  catch
    _, _ -> reply(users, {:error, :failed_to_list_users})
  end

  def handle_call(:list, _from, users) do
    users |> reply(users)
  end

  def handle_call({:list, search_term}, _from, users) do
    # Don't perform filtering if search term is empty
    if search_term == "" do
      filtered =
        Enum.filter(users, fn
          %{name: nil} -> false
          _ -> true
        end)

      users |> reply(filtered)
    else
      # Convert search term to lowercase for case-insensitive comparison
      downcased_term = String.downcase(search_term)

      filtered =
        Enum.filter(users, fn
          %{name: nil} ->
            false

          %{name: name} ->
            name && String.contains?(String.downcase(name), downcased_term)

          _ ->
            false
        end)

      users |> reply(filtered)
    end
  end

  def handle_cast({:put, user}, users) do
    [user | users]
    |> Enum.uniq_by(& &1.pub_key)
    |> Enum.sort_by(&"#{&1.name} #{&1.pub_key}")
    |> noreply()
  end

  def handle_cast({:forget, key}, users) do
    users
    |> Enum.reject(&(&1.pub_key == key))
    |> noreply()
  end
end
