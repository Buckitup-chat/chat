defmodule ChatWeb.MainLive.Page.RecoverKeyShare do
  @moduledoc "Recover Key Share Page"
  use ChatWeb, :live_component

  alias Chat.KeyShare

  alias Ecto.Changeset

  def mount(socket) do
    {:ok,
     socket
     |> assign(:shares, [])
     |> assign(:user_recovery_hash, nil)
     |> assign(
       :changeset,
       Changeset.change({%{}, schema()})
     )}
  end

  def handle_event("save", _, socket) do
    socket |> noreply()
  end

  def handle_event("cancel", %{"ref" => ref}, socket) do
    socket
    |> remove_share(ref)
    |> cancel_upload(:recovery_keys, ref)
    |> check_shares()
    |> noreply()
  end

  def handle_event("accept", _, %{assigns: %{shares: shares}} = socket) do
    key =
      shares
      |> Enum.map(&Map.get(&1, :key))
      |> Enigma.recover_secret_from_shares()

    # do login with key
    socket |> noreply()
  end

  def handle_progress(:recovery_keys, %{done?: true} = _entry, socket) do
    socket
    |> read_file()
    |> read_result()
    |> check_shares()
    |> noreply()
  end

  def handle_progress(_file, _entry, socket) do
    socket |> noreply()
  end

  def read_file(%{assigns: %{shares: _shares}} = socket) do
    case uploaded_entries(socket, :recovery_keys) do
      {[_ | _] = entries, []} ->
        socket = socket |> set_recovery_hash(List.first(entries).client_name)

        uploaded_shares =
          for entry <- entries do
            consume_uploaded_entry(socket, entry, fn %{path: path} ->
              {:postpone,
               %{
                 key: File.read!(path) |> Base.decode64!(),
                 name: entry.client_name,
                 ref: entry.ref,
                 valid: socket |> valid_entry?(entry.client_name)
               }}
            end)
          end

        {:noreply, update(socket, :shares, &uploaded_shares(&1, uploaded_shares))}

      _ ->
        {:noreply, socket}
    end
  end

  def container(assigns) do
    ~H"""
    <div>
      <div :if={!Enum.empty?(@shares)} class="max-w-sm w-full lg:max-w-full lg:flex">
        <div class="border-r border-b border-l border-gray-400 lg:border-l-0 lg:border-t lg:border-gray-400 bg-white rounded-b lg:rounded-b-none lg:rounded-r p-4 flex flex-col justify-between leading-normal">
          <div class="mb-8">
            <div class="text-gray-900 items-center mb-2">
              <span
                :for={share <- @shares}
                class={"inline-flex rounded-md #{if share.valid do "bg-gray-50" else "bg-red-100" end} px-2 py-1 my-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"}
              >
                <.share share={share} myself={@myself} />
              </span>
              <%= error_tag(@form, :shares) %>
            </div>
          </div>
          <div class="flex items-center"></div>
        </div>
      </div>
      <input
        :if={!Enum.empty?(@shares)}
        style="background-color: white;"
        class="w-full h-11 mt-7 bg-transparent text-black py-2 px-4 border border-gray/0 rounded-lg flex items-center justify-center disabled:opacity-50 cursor-pointer"
        type="button"
        value="Accept"
        phx-click="accept"
        phx-target={@myself}
        disabled={!@changeset.valid?}
      />
    </div>
    """
  end

  def share(assigns) do
    ~H"""
    <%= @share.name %>
    <button
      type="button"
      phx-click="cancel"
      phx-value-ref={@share.ref}
      aria-label="cancel"
      phx-target={@myself}
    >
      <.icon id="close" class="w-4 h-4 fill-black" />
    </button>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <img class="vectorGroup bottomVectorGroup" src="/images/bottom_vector_group.svg" />
      <img class="vectorGroup topVectorGroup" src="/images/top_vector_group.svg" />
      <div class="flex flex-col items-center justify-center w-screen h-screen">
        <div class="container unauthenticated z-10">
          <div class="flex justify-center">
            <.icon id="logo" class="w-14 h-14 fill-white" />
          </div>
          <div class="left-0 mt-10">
            <a
              phx-click="login:recovery-key-close"
              class="x-back-target flex items-center justify-start"
            >
              <.icon id="arrowLeft" class="w-4 h-4 fill-white/70" />
              <p class="ml-2 text-sm text-white/70">Back to Log In</p>
            </a>
            <h1
              style="font-size: 28px; line-height: 34px;"
              class="mt-5 font-inter font-bold text-white"
            >
              Recover key from Social Sharing
            </h1>
            <p class="mt-2.5 font-inter text-sm text-white/70">
              <%= if KeyShare.threshold() > Enum.count(@shares) do %>
                Please, upload at least
                <a class="font-bold"><%= KeyShare.threshold() - Enum.count(@shares) %></a>
                share files to recover your key
              <% else %>
                You have uploaded enough files to recover the key
              <% end %>
            </p>
          </div>
          <%= if @step == :initial do %>
            <div class="row">
              <.form
                :let={f}
                for={@changeset}
                as={:recovery_keys}
                id="recover-keys-form"
                class="column "
                phx-change="save"
                phx-submit="save"
                phx-target={@myself}
              >
                <%= live_file_input(@uploads.recovery_keys, style: "display: none") %>
                <input
                  style="background-color: rgb(36, 24, 36);"
                  class="w-full h-11 mt-7 bg-transparent text-white py-2 px-4 border border-white/0 rounded-lg flex items-center justify-center"
                  type="button"
                  value="Upload Key Files"
                  onclick="event.target.parentNode.querySelector('input[type=file]').click()"
                />
                <.container changeset={@changeset} shares={@shares} form={f} myself={@myself} />
              </.form>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp uploaded_shares(shares, upload_shares) do
    upload_shares |> Kernel.--(shares) |> Kernel.++(shares)
  end

  defp remove_share(socket, ref),
    do: socket |> assign(:shares, Enum.filter(socket.assigns.shares, &(&1.ref != ref)))

  defp set_recovery_hash(%{assigns: %{shares: []}} = socket, client_name) do
    socket
    |> assign(
      :user_recovery_hash,
      extract_user_hash(client_name)
    )
  end

  defp set_recovery_hash(socket, _), do: socket

  defp extract_user_hash(client_name) do
    ~r/This is my ID (\w+-\w+)/
    |> Regex.run(client_name)
    |> List.last()
  end

  defp valid_entry?(%{assigns: %{user_recovery_hash: user_recovery_hash}}, client_name) do
    user_recovery_hash == extract_user_hash(client_name)
  end

  defp check_shares(%{assigns: %{shares: _shares} = params} = socket) do
    changeset =
      {%{}, schema()}
      |> Changeset.cast(params, schema() |> Map.keys())
      |> Changeset.validate_required(:shares)
      |> Changeset.validate_length(:shares, min: 4)
      |> shares_validity()
      |> Map.put(:action, :validate)

    socket |> assign(:changeset, changeset)
  end

  defp schema, do: %{shares: {:array, :map}}

  defp shares_validity(%Changeset{changes: %{shares: []}} = changeset), do: changeset

  defp shares_validity(%Changeset{changes: %{shares: shares}} = changeset) do
    case Enum.all?(shares, fn share -> share.valid end) do
      true ->
        changeset

      false ->
        Changeset.add_error(
          changeset,
          :shares,
          "username-hash code is different from a first uploaded key share"
        )
    end
  end

  defp read_result({_, result}), do: result
end
