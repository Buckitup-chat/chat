defmodule ChatWeb.MainLive.Page.KeyShareForm do
  @moduledoc "Represent key share form"

  use ChatWeb, :live_component

  alias Chat.{Dialogs, Messages}
  alias Chat.KeyShare

  alias Ecto.Changeset

  alias ChatWeb.MainLive.Layout

  alias Phoenix.PubSub

  def mount(socket) do
    {:ok, socket |> assign(:share_users, [])}
  end

  def assign_changeset(socket) do
    socket
    |> assign(
      :changeset,
      Changeset.change({%{}, schema()})
      |> Changeset.validate_required(:share_users)
      |> Changeset.validate_length(:share_users, min: 4)
    )
  end

  def check_share(%{assigns: %{share_users: _users} = params} = socket) do
    changeset =
      {%{}, schema()}
      |> Changeset.cast(params, schema() |> Map.keys())
      |> Changeset.validate_required(:share_users)
      |> Changeset.validate_length(:share_users, min: 4)
      |> Map.put(:action, :validate)

    socket
    |> assign(:changeset, changeset)
  end

  def handle_event("select-user", %{"user" => user} = _params, socket) do
    socket
    |> selected_user(user)
    |> check_share()
    |> noreply()
  end

  def handle_event(
        "accept-share",
        _params,
        %{
          assigns: %{
            users: user_cards,
            share_users: share_users,
            me: me,
            monotonic_offset: time_offset
          }
        } = socket
      ) do
    {me, user_cards |> Enum.filter(fn user -> user.name in share_users end)}
    |> KeyShare.generate_key_shares()
    |> KeyShare.save_shares({me, time_offset})
    |> Enum.each(&send_share/1)

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
        :let={_f}
        for={@changeset}
        id="share-form"
        phx-change="check-share"
        phx-submit="accept-share"
        phx-target={@myself}
        as={:form_data}
        class="mt-3 w-full"
      >
        <div class="flex h-64 rounded-md">
          <div class="mx-1 flex w-full h-full flex-col border border-gray-300 rounded-md bg-white">
            <div class="text-lg bg-gray-100 rounded-t-md p-2 users-title">Users</div>
            <ul
              class="h-full overflow-y-scroll overflow-x-hidden users-list"
              id="users-list"
              phx-target={@myself}
            >
              <li
                :for={user <- @users}
                :if={user.name != @me.name}
                class={"cursor-pointer" <> if(user.name in @share_users, do: " bg-gray-200 selected-user", else: "")}
                phx-click="select-user"
                phx-target={@myself}
                phx-value-user={user.name}
              >
                <div class="content">
                  <div class="flex-1 px-2 py-2 truncate whitespace-normal">
                    <p class="text-sm font-bold">
                      <div class="flex flex-row px-7">
                        <Layout.Card.hashed_name card={user} />
                      </div>
                    </p>
                  </div>
                </div>
              </li>
            </ul>
          </div>
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

  defp selected_user(%{assigns: %{share_users: users}} = socket, user) do
    case user in users do
      true -> socket |> assign(:share_users, users -- [user])
      false -> socket |> assign(:share_users, users ++ [user])
    end
  end

  defp send_share(%{
         entry: entry,
         dialog: dialog,
         me: me,
         file_info: {file_key, file_secret, time}
       }) do
    entry
    |> Messages.File.new(file_key, file_secret, time)
    |> Dialogs.add_new_message(me, dialog)
    |> broadcast(dialog)
  end

  defp broadcast(message, dialog) do
    PubSub.broadcast!(
      Chat.PubSub,
      dialog
      |> Dialogs.key()
      |> then(&"dialog:#{&1}"),
      {:dialog, {:new_dialog_message, message}}
    )
  end

  defp schema, do: %{share_users: {:array, :string}}
end
