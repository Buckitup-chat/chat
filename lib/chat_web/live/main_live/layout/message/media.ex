defmodule ChatWeb.MainLive.Layout.Message.Media do
  @moduledoc "File, audio and image parts of a message, plus the `:file` assign they render."
  use ChatWeb, :component

  alias Chat.Content.Files
  alias Chat.Messages.ExportHelper
  alias Chat.Utils.StorageId
  alias Phoenix.LiveView.JS

  @doc "Assigns `:file` (name, size, url) for the message — export path or live file url."
  def assign_file(%{export?: true, msg: %{content: json, type: type}} = assigns)
      when type in [:audio, :file, :image, :video] do
    {id, secret} = StorageId.from_json(json)
    [_, _, _, _, name, size] = Files.get(id, secret)

    filename = ExportHelper.get_filename(name, id)

    assign(assigns, :file, %{
      name: name,
      size: size,
      url: "files/" <> filename
    })
  end

  def assign_file(%{msg: msg} = assigns) do
    with %{type: type, file_info: [_, _, _, _, name, size], file_url: url} <- msg,
         true <- type in [:audio, :image, :video, :file],
         true <- String.valid?(name),
         true <- String.valid?(size) do
      %{
        name: name,
        size: size,
        url: url
      }
    else
      _ ->
        %{
          name: "Broken file",
          size: "n/a",
          url: nil
        }
    end
    |> then(&assign(assigns, :file, &1))
  end

  attr :export?, :boolean, required: true, doc: "embed file icon SVG?"
  attr :file, :map, required: true, doc: "file map"
  attr :msg, :map, required: true, doc: "message struct"

  def file(assigns) do
    if assigns.file do
      ~H"""
      <.link class="flex items-center justify-between" href={@file.url}>
        <.file_icon export?={@export?} />

        <div class="w-36 flex flex-col pr-3">
          <span class="truncate text-xs x-file" href={@file.url}>{@file.name}</span>
          <span class="text-xs text-black/50 whitespace-pre-line">{@file.size}</span>
        </div>
      </.link>
      """
    else
      ~H"""
      <div class="flex items-center justify-between">
        Error getting file
      </div>
      """
    end
  end

  attr :file, :map, required: true, doc: "file map"

  def media_file_info(assigns) do
    ~H"""
    <div class="w-full flex flex-row justify-between px-3 py-2">
      <span class="truncate text-xs x-file" href={@file.url}>{@file.name}</span>
      <span class="text-xs text-black/50 whitespace-pre-line">{@file.size}</span>
    </div>
    """
  end

  attr :export?, :boolean, required: true, doc: "show waveform?"
  attr :file, :map, required: true, doc: "file map"
  attr :msg, :map, required: true, doc: "message struct"

  def audio(%{export?: true} = assigns) do
    ~H"""
    <audio src={@file.url} class="a-audio" controls />
    """
  end

  def audio(assigns) do
    ~H"""
    <div class="flex flex-row w-full h-12">
      <button class="play rounder flex justify-center items-center w-3/12">
        <svg class="pause-circle w-9 hidden" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">
          <path
            class="fill-purple"
            d="M24,4A20,20,0,1,0,44,24,20,20,0,0,0,24,4ZM21,33H16V15h5Zm11,0H27V15h5Z"
            transform="translate(-4 -4)"
          >
          </path>
        </svg>
        <svg class="play-circle w-9" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">
          <path
            class="fill-purple"
            d="M24,4A20,20,0,1,0,44,24,20,20,0,0,0,24,4ZM17,33V15l18,9Z"
            transform="translate(-4 -4)"
          >
          </path>
        </svg>
      </button>
      <div
        class="peaks-overview-container flex w-9/12 h-12"
        id={"message-#{@msg.id}-peaks"}
        phx-update="ignore"
      >
      </div>
    </div>
    <audio src={@file.url} class="a-audio hidden" controls />
    """
  end

  attr :chat_type, :atom, required: true, doc: ":dialog or :room"
  attr :export?, :boolean, required: true, doc: "disable image gallery?"
  attr :file, :map, required: true, doc: "file map"
  attr :msg, :map, required: true, doc: "message struct"

  def image(%{export?: true} = assigns) do
    ~H"""
    <.link href={@file.url}>
      <img class="object-cover overflow-hidden" src={@file.url} />
    </.link>
    """
  end

  def image(assigns) do
    ~H"""
    <img
      class="object-cover overflow-hidden"
      src={@file[:url]}
      id={"chat-image-#{@msg.id}"}
      loading="lazy"
      phx-click={open_gallery(@chat_type)}
      phx-value-id={@msg.id}
      phx-value-index={@msg.index}
      phx-hook="ImageForceLoader"
    />
    """
  end

  attr :export?, :boolean, required: true, doc: "embed SVG?"

  defp file_icon(%{export?: true} = assigns) do
    ~H"""
    <svg
      id="document"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      class="w-14 h-14 flex fill-black/50"
    >
      <path
        fill-rule="evenodd"
        d="M4 4a2 2 0 012-2h4.586A2 2 0 0112 2.586L15.414 6A2 2 0 0116 7.414V16a2 2 0 01-2 2H6a2 2 0 01-2-2V4z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp file_icon(assigns) do
    ~H"""
    <.icon id="document" class="w-14 h-14 flex fill-black/50" />
    """
  end

  defp open_gallery(chat_type, js \\ %JS{}) do
    js
    |> JS.push("#{chat_type}/message/open-image-gallery")
    |> JS.add_class("hidden", to: "#chatContent")
    |> JS.remove_class("hidden", to: "#imageGallery")
  end
end
