defmodule ChatWeb.MainLive.Page.Logout do
  @moduledoc "Logout page"
  import Phoenix.LiveView, only: [assign: 3, push_event: 3]

  alias Chat.Actor
  alias Chat.Broker
  alias Chat.Log
  alias ChatWeb.Router.Helpers, as: Routes

  alias Ecto.Changeset

  def init(%{assigns: %{}} = socket) do
    socket
    |> assign(:mode, :logout)
    |> assign(:step, :initial)
  end

  def go_middle(%{assigns: %{}} = socket) do
    socket
    |> assign(:step, :middle)
    |> assign(:changeset, Changeset.change({%{}, schema()}))
  end

  def check_password(socket, form) do
    changeset =
      {%{}, schema()}
      |> Changeset.cast(form, schema() |> Map.keys())
      |> Changeset.validate_length(:password, min: 12)
      |> Changeset.validate_format(:password, ~r/^[0-9A-Za-z]+$/,
        message: "Should consist of letters and numbers"
      )
      |> Changeset.validate_confirmation(:password)
      |> Map.put(:action, :validate)

    socket
    |> assign(:changeset, changeset)
  end

  def download_on_good_password(socket, %{"password" => password} = form) do
    socket
    |> check_password(form)
    |> then(fn %{assigns: %{changeset: %{valid?: is_valid}}} = socket ->
      if is_valid do
        socket
        |> generate_backup(password)
        |> go_final()
      else
        socket
      end
    end)
  end

  def generate_backup(%{assigns: %{me: me, rooms: rooms}} = socket, password) do
    broker_key =
      Actor.new(me, rooms, %{})
      |> Actor.to_encrypted_json(password)
      |> then(&{"#{me.name}.data", &1})
      |> Broker.store()

    me |> Log.self_backup()

    socket
    |> push_event("chat:redirect", %{url: Routes.file_url(socket, :backup, broker_key)})
  end

  def go_final(%{assigns: %{}} = socket) do
    socket
    |> assign(:step, :final)
  end

  def wipe(%{assigns: %{me: me}} = socket) do
    me |> Log.logout()

    socket
    |> assign(:me, nil)
    |> assign(:rooms, nil)
    |> assign(:mode, nil)
    |> assign(:need_login, true)
  end

  def close(%{assigns: %{}} = socket) do
    socket
    |> assign(:step, nil)
    |> assign(:changeset, nil)
  end

  defp schema do
    %{password: :string, password_confirmation: :string}
  end
end
