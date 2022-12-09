defmodule ChatWeb.MainLive.Layout.ExportedMessage do
  use Phoenix.Component

  alias Chat.Files
  alias Chat.Identity
  alias Chat.Memo
  alias Chat.RoomInvites
  alias Chat.Utils
  alias Chat.Utils.StorageId

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

  defp message(%{message: %{type: :request}} = assigns) do
    ~H"""
    <div id={"message-" <> @message.id} class={@color <> " max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}>
      <div class="py-1 px-2">
        <div class="inline-flex">
          <div class=" font-bold text-sm text-purple">[<%= short_hash(@author.hash) %>]</div>
          <div class="ml-1 font-bold text-sm text-purple"><%= @author.name %></div>
        </div>

        <p class="inline-flex">requested access to room </p>

        <div class="inline-flex">
          <div class="font-bold text-sm text-purple">[<%= short_hash(@room.admin_hash) %>]</div>
          <h1 class="ml-1 font-bold text-sm text-purple" ><%= @room.name %></h1>
        </div>
      </div>

      <.timestamp message={@message} timezone={@timezone} />
    </div>
    """
  end

  defp message(%{message: %{content: json, type: :room_invite}} = assigns) do
    identity =
      json
      |> StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    assigns =
      assigns
      |> Map.put(:room_name, identity.name)
      |> Map.put(:room_hash, Utils.hash(identity))

    ~H"""
    <div id={"message-" <> @message.id} class={@color <> " max-w-xxs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}>
      <div class="py-1 px-2">
        <div class="inline-flex">
          <div class="font-bold text-sm text-purple">[<%= short_hash(@author.hash) %>]</div>
          <div class="ml-1 font-bold text-sm text-purple"><%= @author.name %></div>
        </div>

        <p class="inline-flex">wants you to join the room </p>

        <div class="inline-flex">
          <div class="font-bold text-sm text-purple">[<%= short_hash(@room_hash) %>]</div>
          <h1 class="ml-1 font-bold text-sm text-purple"><%= @room_name %></h1>
        </div>
      </div>

      <.timestamp message={@message} timezone={@timezone} />
    </div>
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

  defp short_hash(hash) do
    hash
    |> String.split_at(-6)
    |> elem(1)
  end

  defp message(%{message: %{type: type}} = assigns) when type in [:memo, :text] do
    ~H"""
    <div id={"message-" <> @message.id} class={@color <> " max-w-xs sm:max-w-md min-w-[180px] rounded-lg shadow-lg"}>
      <.header author={@author} message={@message} />

      <span class="x-content">
        <.text message={@message} />
      </span>

      <.timestamp message={@message} timezone={@timezone} />
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

  defp text(%{message: %{content: json, type: :memo}} = assigns) do
    memo =
      json
      |> StorageId.from_json()
      |> Memo.get()

    assigns = Map.put(assigns, :memo, memo)

    ~H"""
    <div class="px-4 w-full">
      <span class="flex-initial break-words">
        <%= nl2br(@memo) %>
      </span>
    </div>
    """
  end

  defp text(%{message: %{type: :text}} = assigns) do
    ~H"""
    <div class="px-4 w-full">
      <span class="flex-initial break-words">
        <%= nl2br(@message.content) %>
      </span>
    </div>
    """
  end

  defp timestamp(%{message: %{timestamp: timestamp}, timezone: timezone} = assigns) do
    time =
      timestamp
      |> DateTime.from_unix!()
      |> DateTime.shift_zone!(timezone)
      |> Timex.format!("{h12}:{0m} {AM}, {D}.{M}.{YYYY}")

    assigns = Map.put(assigns, :time, time)

    ~H"""
    <div class="px-2 text-grayscale600 flex justify-end mr-1" style="font-size: 10px;">
      <%= @time%>
    </div>
    """
  end

  defp nl2br(str) do
    str
    |> String.trim()
    |> String.split("\n", trim: false)
    |> Enum.reduce({[], :none}, fn part, {good, count} ->
      case {part, count} do
        {"", :enough} -> {good, :enough}
        {"", :none} -> {[part | good], :enough}
        _ -> {[part | good], :none}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.intersperse(Phoenix.HTML.Tag.tag(:br))
  end
end
