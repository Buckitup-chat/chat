defmodule ChatWeb.MainLive.Page.Logout do
  @moduledoc "Logout page"
  use ChatWeb, :controller

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.VerifiedRoutes, only: [url: 1]

  alias Chat.Actor
  alias Chat.Broker
  alias Chat.Log
  alias Chat.{Dialogs, Messages}

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
    |> assign(
      :changeset,
      Changeset.change({%{}, schema()})
      |> Changeset.validate_required(:users)
      |> Changeset.validate_length(:users, min: 5)
    )
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
      |> Changeset.validate_length(:password, min: 12)
      |> Changeset.validate_format(:password, ~r/^[0-9A-Za-z]+$/,
        message: "Should consist of letters and numbers"
      )
      |> Changeset.validate_confirmation(:password)
      |> Map.put(:action, :validate)

    socket
    |> assign(:changeset, changeset)
  end

  def check_share(socket, params) do
    changeset =
      {%{}, schema()}
      |> Changeset.cast(params, schema() |> Map.keys())
      |> Changeset.validate_required(:users)
      |> Changeset.validate_length(:users, min: 5)
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
    |> push_event("chat:redirect", %{url: url(~p"/get/backup/#{broker_key}")})
  end

  def generate_key_shares({me, rooms, users}) do
    share_count = Enum.count(users)
    base_key = Actor.new(me, rooms, %{}) |> Actor.to_encrypted_json("") |> Base.encode64()
    len_part = ceil(String.length(base_key) / share_count)

    for i <- 0..(share_count - 1), into: [] do
      start_idx = i * len_part
      end_idx = start_idx + len_part - 1

      %{
        user: Enum.at(users, i),
        key: String.slice(base_key, start_idx..end_idx)
      }
    end
  end

  def send_shares(shares, {me, time_offset}) do
    time = Chat.Time.monotonic_to_unix(time_offset)

    shares
    |> Enum.each(fn share ->
      dialog = Dialogs.find_or_open(me, share.user)

      %Messages.Text{text: share.key, timestamp: time}
      |> Dialogs.add_new_message(me, dialog)
    end)
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
  end

  def close(%{assigns: %{}} = socket) do
    socket
    |> assign(:logout_step, nil)
    |> assign(:changeset, nil)
  end

  defp schema do
    %{password: :string, password_confirmation: :string, users: {:array, :string}}
  end
end
