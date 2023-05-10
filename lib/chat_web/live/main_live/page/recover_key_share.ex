defmodule ChatWeb.MainLive.Page.RecoverKeyShare do
  @moduledoc "Recover Key Share Page"
  use ChatWeb, :live_component

  alias Chat.KeyShare

  alias Chat.Identity

  alias Ecto.Changeset

  def mount(socket) do
    {:ok,
     socket
     |> assign(:shares, MapSet.new())
     |> assign(:hash_sign, nil)
     |> assign(:recovery_error, nil)
     |> assign(
       :changeset,
       Changeset.change({%{}, schema()})
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
         is_valid_sign <- Enigma.is_valid_sign?(sign, my_hash, me.public_key) do
      socket |> sign_based_response(me, is_valid_sign)
    else
      :user_keystring_broken ->
        socket |> assign(:recovery_error, "Unable to detect user from social parts") |> noreply()
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
          for entry <- entries, into: MapSet.new() do
            consume_uploaded_entry(socket, entry, fn %{path: path} ->
              {key, hash_sign} = path |> KeyShare.read_content()

              {:ok,
               %{
                 key: key,
                 hash_sign: hash_sign,
                 name: entry.client_name,
                 ref: entry.ref
               }}
            end)
          end

        update(socket, :shares, &KeyShare.compose(&1, uploaded_shares))

      _ ->
        socket
    end
  end

  def container(assigns) do
    ~H"""
    <div>
      <div :if={!Enum.empty?(@shares)} class="w-full lg:max-w-full">
        <div class="border-r border-b border-l border-gray-400 lg:border-l-0 lg:border-t lg:border-gray-400 bg-white rounded-b lg:rounded-b-none lg:rounded-r p-4 flex flex-col justify-between leading-normal">
          <div class="mb-2">
            <div class="text-gray-900 items-center mb-2">
              <span
                :for={share <- @shares}
                class={"inline-flex rounded-md #{share.bg} px-2 py-1 my-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"}
              >
                <.share share={share} myself={@myself} />
              </span>
            </div>
          </div>

          <.validation_box shares={@shares} />
          <div
            :if={@recovery_error}
            class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded relative text-center"
            role="alert"
          >
            <span class="block sm:inline">
              <%= @recovery_error %>
            </span>
          </div>
        </div>
      </div>
      <input
        :if={!Enum.empty?(@shares)}
        style="background-color: white;"
        class="w-full h-11 mt-5 bg-transparent text-black py-2 px-4 border border-gray/0 rounded-lg flex items-center justify-center disabled:opacity-50 cursor-pointer"
        type="button"
        value="Accept"
        phx-click="accept"
        phx-target={@myself}
        disabled={!@changeset.valid?}
      />
    </div>
    """
  end

  defp validation_box(assigns) do
    ~H"""
    <div class="inline-flex px-2">
      <div :if={Enum.any?(@shares, & &1.duplicate)} class="px-2">
        <span class="dot-yellow w-full mx-1"></span>
        <a class="text-xs font-small">Duplicates</a>
      </div>
      <div :if={Enum.any?(@shares, &(!&1.valid))} class="px-2">
        <span class="dot-red w-full mx-1"></span>
        <a class="text-xs font-small">Different</a>
      </div>
    </div>
    <div
      :if={Enum.any?(@shares, &(!&1.valid)) || Enum.any?(@shares, & &1.duplicate)}
      class="border border-gray-400 rounded-md items-center justify-center bg-white max-w-sm w-full lg:max-w-full lg:flex mt-2 px-2 py-1 text-sm font-medium"
    >
      <span>
        Please remove
        <a :if={Enum.any?(@shares, & &1.duplicate)} class="text-red-400"> duplicates </a>
        <a :if={Enum.any?(@shares, &(!&1.valid)) && Enum.any?(@shares, & &1.duplicate)}>
          and
        </a>
        <a :if={Enum.any?(@shares, &(!&1.valid))} class="text-red-400"> different </a>
        <a :if={Enum.any?(@shares, &(!&1.valid))}> user files </a>
      </span>
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

  defp remove(socket, ref),
    do: socket |> assign(:shares, Enum.filter(socket.assigns.shares, &(&1.ref != ref)))

  defp set_hash_sign(%{assigns: %{shares: shares, hash_sign: _hash_sign}} = socket) do
    case Enum.empty?(shares) do
      true ->
        socket |> assign(:hash_sign, nil)

      _ ->
        socket
        |> assign(
          :hash_sign,
          shares |> Enum.min_by(&(&1.ref |> String.to_integer())) |> Map.get(:hash_sign)
        )
    end
  end

  defp validate_hash(%{assigns: %{shares: shares, hash_sign: hash_sign}} = socket) do
    socket
    |> assign(
      :shares,
      shares
      |> Enum.map(fn share ->
        Map.put(share, :valid, share.hash_sign == hash_sign)
      end)
    )
  end

  defp check(%{assigns: %{shares: _shares} = params} = socket) do
    changeset =
      {%{}, schema()}
      |> Changeset.cast(params, schema() |> Map.keys())
      |> Changeset.validate_required(:shares)
      |> Changeset.validate_length(:shares, min: 4)
      |> validate_user_hash()
      |> validate_unique()
      |> Map.put(:action, :validate)

    socket |> assign(:changeset, changeset)
  end

  defp schema, do: %{shares: {:array, :map}}

  defp validate_unique(%Changeset{changes: %{shares: []}} = changeset), do: changeset

  defp validate_unique(%Changeset{changes: %{shares: shares}} = changeset) do
    duplicates = shares |> KeyShare.look_for_duplicates()

    case duplicates do
      [] ->
        changeset

      _ ->
        Changeset.add_error(
          changeset,
          :shares,
          "duplicates are found: #{Enum.map(duplicates, & &1.ref)}"
        )
    end
  end

  defp validate_user_hash(%Changeset{changes: %{shares: []}} = changeset), do: changeset

  defp validate_user_hash(%Changeset{changes: %{shares: shares}} = changeset) do
    case Enum.all?(shares, fn share -> share.valid end) do
      true ->
        changeset

      false ->
        Changeset.add_error(
          changeset,
          :shares,
          "mismatch: different user file"
        )
    end
  end

  defp mark_duplicates(%{assigns: %{shares: shares}} = socket) do
    duplicates_list = shares |> KeyShare.look_for_duplicates()
    exclude_list = duplicates_list |> Enum.map(& &1.exclude)
    index_list = duplicates_list |> Enum.map(& &1.ref) |> List.flatten()

    shares =
      shares
      |> Enum.map(fn share ->
        case share.ref in index_list && share.ref not in exclude_list && share.valid do
          true -> Map.put(share, :duplicate, true)
          false -> Map.put(share, :duplicate, false)
        end
      end)

    socket |> assign(:shares, shares)
  end

  defp set_bg(%{assigns: %{shares: shares}} = socket) do
    socket
    |> assign(
      :shares,
      shares
      |> Enum.map(fn share ->
        case {share.valid, share.duplicate} do
          {true, false} -> Map.put(share, :bg, "bg-gray-50")
          {true, true} -> Map.put(share, :bg, "bg-yellow-50")
          _ -> Map.put(share, :bg, "bg-red-50")
        end
      end)
    )
  end

  defp sort(%{assigns: %{shares: shares}} = socket) do
    valid_shares = shares |> Enum.filter(& &1.valid)
    invalid_shares = shares |> Enum.reject(& &1.valid)

    socket
    |> assign(
      :shares,
      valid_shares
      |> Enum.sort_by(&{&1.key, &1.duplicate})
      |> Enum.concat(invalid_shares)
    )
  end

  defp sign_based_response(socket, me, true) do
    Process.send(self(), {:key_recovered, [me, []]}, [])
    socket |> noreply()
  end

  defp sign_based_response(socket, _me, _not_valid),
    do: socket |> assign(:recovery_error, "Invalid recovery signature") |> noreply()

  defp clean_recovery_error(socket), do: socket |> assign(:recovery_error, nil)
end
