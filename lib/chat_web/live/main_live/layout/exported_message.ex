defmodule ChatWeb.MainLive.Layout.ExportedMessage do
  use Phoenix.Component

  alias Chat.Files
  alias Chat.Identity
  alias Chat.Memo
  alias Chat.RoomInvites
  alias Chat.Utils
  alias Chat.Utils.StorageId
  alias ChatWeb.MainLive.Layout.Message

  def message_block(assigns) do
    ~H"""
    <div class="messageBlock flex flex-row px-2 sm:px-8">
      <div class="m-1 w-full flex justify-start" id={"dialog-message-" <> @message.id}>
        <.message
          author={@author}
          color="bg-white"
          message={@message}
          room={@room}
          timezone={@timezone}
        />
      </div>
    </div>
    """
  end

  defp message(%{message: %{type: :file}} = assigns) do
    assigns = assign_file(assigns)

    ~H"""
    <div id={"message-" <> @message.id} class={@color <> " max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}>
      <.header author={@author} message={@message} />

      <div class="flex items-center justify-between">
        <svg id="document" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" class="w-14 h-14 flex fill-black/50">
          <path fill-rule="evenodd" d="M4 4a2 2 0 012-2h4.586A2 2 0 0112 2.586L15.414 6A2 2 0 0116 7.414V16a2 2 0 01-2 2H6a2 2 0 01-2-2V4z" clip-rule="evenodd" />
        </svg>

        <div class="w-36 flex flex-col pr-3">
          <span class="truncate text-xs x-file" href={@file.url}><%= @file.name %></span>
          <span class="text-xs text-black/50 whitespace-pre-line"><%= @file.size %></span>
        </div>
      </div>

      <.timestamp message={@message} timezone={@timezone} />
    </div>
    """
  end

  defp message(%{message: %{type: :image}} = assigns) do
    assigns = assign_file(assigns)

    ~H"""
    <div id={"message-" <> @message.id} class={@color <> " max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}>
      <.header author={@author} message={@message} />
      <.timestamp message={@message} timezone={@timezone} />
      <img class="object-cover overflow-hidden" src={@file.url} />
    </div>
    """
  end

  defp message(%{message: %{type: :video}} = assigns) do
    assigns = assign_file(assigns)

    ~H"""
    <div id={"message-" <> @message.id} class={@color <> " max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg x-download"}>
      <.header author={@author} message={@message} />
      <.timestamp message={@message} timezone={@timezone} />
      <video src={@file.url} class="a-video" controls />
    </div>
    """
  end

  defp message(assigns) do
    ~H"""
    <Message.render
      author={@author}
      color="bg-white"
      header={}
      is_mine={false}
      msg={@message}
      room={@room}
      timezone={@timezone}>
      <:message_header>
        <.header author={@author} message={@message} />
      </:message_header>
    </Message.render>
    """
  end

  defp header(assigns) do
    ~H"""
    <div id={"message-header-" <> @message.id} class="py-1 px-2 flex items-center justify-between relative">
      <div class="flex flex-row">
        <div class="text-sm text-grayscale600">[<%= short_hash(@author.hash) %>]</div>
        <div class="ml-1 font-bold text-sm text-purple"><%= @author.name %></div>
      </div>
    </div>
    """
  end

  defp short_hash(hash) do
    hash
    |> String.split_at(-6)
    |> elem(1)
  end

  defp timestamp(assigns) do
    ~H"""
    <Message.message_timestamp msg={@message} timezone={@timezone} />
    """
  end

  defp assign_file(%{message: %{content: json}} = assigns) do
    {id, secret} = StorageId.from_json(json)
    [_, _, _, _, name, size] = Files.get(id, secret)

    {extension, filename} =
      name
      |> String.split(".")
      |> List.pop_at(-1)

    filename = Enum.join(filename, ".") <> "_" <> id <> "." <> extension

    Map.put(assigns, :file, %{
      name: name,
      size: size,
      url: "files/" <> filename
    })
  end
end
