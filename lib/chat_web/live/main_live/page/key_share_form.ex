defmodule ChatWeb.MainLive.Page.KeyShareForm do
  @moduledoc "Represent key share form"

  use ChatWeb, :live_component

  alias Chat.KeyShare

  alias Ecto.Changeset

  def assign_changeset(socket) do
    socket
    |> assign(
      :changeset,
      Changeset.change({%{}, schema()})
      |> Changeset.validate_required(:users)
      |> Changeset.validate_length(:users, min: 4)
    )
  end

  def check_share(socket, params) do
    changeset =
      {%{}, schema()}
      |> Changeset.cast(params, schema() |> Map.keys())
      |> Changeset.validate_required(:users)
      |> Changeset.validate_length(:users, min: 4)
      |> Map.put(:action, :validate)

    socket
    |> assign(:changeset, changeset)
  end

  def handle_event("check-share", %{"form_data" => %{"users" => _users} = params}, socket) do
    socket
    |> check_share(params)
    |> noreply()
  end

  def handle_event(
        "accept-share",
        %{"form_data" => %{"users" => users}},
        %{assigns: %{users: user_cards, me: me, rooms: rooms, monotonic_offset: time_offset}} =
          socket
      ) do
    {me, rooms, user_cards |> Enum.filter(fn user -> user.name in users end)}
    |> KeyShare.generate_key_shares()
    |> KeyShare.send_shares({me, time_offset})

    send(self(), {:key_shared, []})

    socket
    |> noreply()
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-base font-bold text-grayscale">Share the Key</h1>
      <p class="mt-3 text-sm text-black/50">
        To store the backup copy of the key securely, select at least 4 users who will store a parts of your key.
      </p>
      <.form
        :let={f}
        for={@changeset}
        id="share-form"
        phx-change="check-share"
        phx-submit="accept-share"
        phx-target={@myself}
        as={:form_data}
        class="mt-3 w-full"
      >
        <div class="mt-3 w-ull relative">
          <%= multiple_select(
            f,
            :users,
            @users
            |> Enum.map(fn user -> user.name end)
            |> List.delete(@me.name),
            class:
              "form-select block w-full py-2 px-3 rounded-md shadow-sm transition ease-in-out duration-150 sm:text-sm sm:leading-5"
          ) %>
        </div>
        <%= submit("Share",
          phx_disable_with: "Sharing the Key...",
          class: "mt-5 w-full h-12 border-0 rounded-lg bg-grayscale text-white disabled:opacity-50",
          disabled: !@changeset.valid?
        ) %>
      </.form>
    </div>
    """
  end

  def schema, do: %{users: {:array, :string}}
end
