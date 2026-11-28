defmodule ChatWeb.MainLive.Page.RecoverKeyShare do
  @moduledoc """
  Recover Key Share Page: the LiveComponent (callbacks, upload handling, markup).
  Delegates to

  - `ChatWeb.MainLive.Page.RecoverKeyShare.Shares` — share list state and validation
  - `ChatWeb.MainLive.Page.RecoverKeyShare.Components` — share list markup
  """
  use ChatWeb, :live_component

  import ChatWeb.MainLive.Page.RecoverKeyShare.Components
  import ChatWeb.MainLive.Page.RecoverKeyShare.Shares

  alias Chat.Identity
  alias Chat.KeyShare

  def mount(socket) do
    {:ok,
     socket
     |> assign(:shares, MapSet.new())
     |> assign(:hash_sign, nil)
     |> assign(:recovery_error, nil)
     |> assign(
       :changeset,
       KeyShare.changeset()
     )}
  end

  def handle_event("save", _, socket) do
    socket |> clean_recovery_error() |> noreply()
  end

  def handle_event("cancel", %{"ref" => ref}, socket) do
    socket
    |> remove(ref)
    |> set_hash_sign()
    |> mark_duplicates()
    |> check()
    |> set_bg()
    |> clean_recovery_error()
    |> noreply()
  end

  def handle_event("accept", _, %{assigns: %{shares: shares, hash_sign: sign}} = socket) do
    keystring =
      shares
      |> Enum.map(&Map.get(&1, :key))
      |> Enigma.recover_secret_from_shares()

    with {:ok, user} <- KeyShare.user_in_share(keystring),
         %Identity{} = me <- [user.name, keystring] |> Identity.from_strings(),
         my_hash <- me.private_key |> Enigma.hash(),
         is_valid_sign <- Enigma.valid_sign?(sign, my_hash, me.public_key) do
      socket |> sign_based_response(me, is_valid_sign)
    else
      :user_keystring_broken ->
        shares = shares |> KeyShare.filter_out_broken()

        socket
        |> assign(:recovery_error, "Unable to detect user from social parts")
        |> assign(:shares, shares)
        |> set_bg()
        |> sort()
        |> noreply()
    end
  end

  def handle_progress(:recovery_keys, %{done?: true} = _entry, socket) do
    socket
    |> read_file()
    |> set_hash_sign()
    |> validate_hash()
    |> mark_duplicates()
    |> check()
    |> set_bg()
    |> sort()
    |> noreply()
  end

  def handle_progress(_file, _entry, socket) do
    socket |> noreply()
  end

  def read_file(%{assigns: %{shares: _shares}} = socket) do
    case uploaded_entries(socket, :recovery_keys) do
      {[_ | _] = entries, []} ->
        uploaded_shares =
          for entry <- entries, into: MapSet.new(), do: consume_share(socket, entry)

        socket = check_broken_content(socket, uploaded_shares)
        update(socket, :shares, &KeyShare.compose(&1, uploaded_shares))

      _ ->
        socket
    end
  end

  defp consume_share(socket, entry) do
    consume_uploaded_entry(socket, entry, fn %{path: path} -> share_from_upload(path, entry) end)
  end

  def share_from_upload(path, entry) do
    case path |> KeyShare.read_content() do
      :error ->
        {:ok,
         %{
           key: "",
           hash_sign: "",
           name: entry.client_name,
           ref: entry.ref,
           broken: true
         }}

      [key, hash_sign] ->
        {:ok,
         %{
           key: key,
           hash_sign: hash_sign,
           name: entry.client_name,
           ref: entry.ref
         }}
    end
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
                <a class="font-bold">{KeyShare.threshold() - Enum.count(@shares)}</a>
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
                <.live_file_input upload={@uploads.recovery_keys} style="display: none" />
                <input
                  style="background-color: rgb(36, 24, 36);"
                  class="w-full h-11 mt-7 bg-transparent text-white py-2 px-4 border border-white/0 rounded-lg flex items-center justify-center"
                  type="button"
                  value="Upload Key Files"
                  onclick="event.target.parentNode.querySelector('input[type=file]').click()"
                />
                <.container
                  changeset={@changeset}
                  shares={@shares}
                  form={f}
                  myself={@myself}
                  recovery_error={@recovery_error}
                />
              </.form>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp sign_based_response(socket, me, true) do
    Process.send(self(), {:key_recovered, [me, []]}, [])
    socket |> noreply()
  end

  defp sign_based_response(socket, _me, _not_valid),
    do: socket |> assign(:recovery_error, "Invalid recovery signature") |> noreply()
end
