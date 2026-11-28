defmodule ChatWeb.MainLive.Page.RecoverKeyShare.Components do
  @moduledoc """
  Markup of the uploaded share list on the recover key share page: the share chips,
  the duplicates/different-user hints, the recovery error and the accept button.

  Part of the `ChatWeb.MainLive.Page.RecoverKeyShare` namespace.
  """

  use Phoenix.Component

  import ChatWeb.LiveHelpers, only: [icon: 1]

  alias Chat.KeyShare

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
              {@recovery_error}
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
        disabled={!@changeset.valid? || Enum.any?(@shares, &KeyShare.broken?/1)}
      />
    </div>
    """
  end

  def validation_box(assigns) do
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
    {@share.name}
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
end
