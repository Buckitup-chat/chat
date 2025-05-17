defmodule ChatWeb.MainLive.Page.Logout do
  @moduledoc "Logout page"
  use ChatWeb, :live_view

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Chat.Actor
  alias Chat.Broker
  alias Chat.Log

  alias Ecto.Changeset

  alias ChatWeb.MainLive.Page

  def init(%{assigns: %{}} = socket) do
    socket
    |> assign(:logout_step, nil)
  end

  def open(%{assigns: %{}} = socket) do
    socket
    |> assign(:logout_step, :initial)
  end

  def go_middle(%{assigns: %{}} = socket) do
    socket
    |> assign(:logout_step, :middle)
    |> assign(
      :changeset,
      Changeset.change({%{}, schema()}) |> Changeset.validate_required([:password])
    )
    |> assign(:is_password_visible, false)
    |> assign(:is_password_confirmation_visible, false)
  end

  def go_share(%{assigns: %{}} = socket) do
    socket
    |> assign(:logout_step, :share)
  end

  def toggle_password_visibility(%{assigns: %{is_password_visible: flag}} = socket) do
    socket
    |> assign(:is_password_visible, !flag)
  end

  def toggle_password_confirmation_visibility(
        %{assigns: %{is_password_confirmation_visible: flag}} = socket
      ) do
    socket
    |> assign(:is_password_confirmation_visible, !flag)
  end

  def check_password(socket, form) do
    changeset =
      {%{}, schema()}
      |> Changeset.cast(form, schema() |> Map.keys())
      |> Changeset.validate_required([:password, :password_confirmation])
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

  def generate_backup(
        %{assigns: %{me: me, rooms: rooms, monotonic_offset: time_offset}} = socket,
        password
      ) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    broker_key =
      Actor.new(me, rooms, %{})
      |> Actor.to_encrypted_json(password)
      |> then(&{"#{me.name}.data", &1})
      |> Broker.store()

    me |> Log.self_backup(time)

    socket
    |> Page.Login.reset_rooms_to_backup(sync: true)
    |> push_event("chat:redirect", %{url: path(socket, ~p"/get/backup/#{broker_key}")})
  end

  def go_final(%{assigns: %{}} = socket) do
    socket
    |> assign(:logout_step, :final)
  end

  def wipe(%{assigns: %{me: me, monotonic_offset: time_offset}} = socket) do
    time = Chat.Time.monotonic_to_unix(time_offset)
    me |> Log.logout(time)

    socket
    |> assign(:me, nil)
    |> assign(:rooms, nil)
    |> assign(:mode, nil)
    |> assign(:need_login, true)
    |> push_event("clear", %{})
  end

  def close(%{assigns: %{}} = socket) do
    socket
    |> assign(:logout_step, nil)
    |> assign(:changeset, nil)
  end

  defp schema do
    %{password: :string, password_confirmation: :string}
  end
end
