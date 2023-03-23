defmodule NaiveApi.Message do
  @moduledoc "Message resolvers"
  use NaiveApi, :resolver
  alias Chat.Content.{Files, Memo, RoomInvites}
  alias Chat.Identity
  alias Chat.Utils
  alias Chat.Utils.StorageId
  alias ChatWeb.Utils, as: WebUtils

  def fill_content(%{type: :text, content: content}, _, _),
    do: %{__typename: :text_content, text: Utils.trim_text(content)} |> ok()

  def fill_content(%{type: :memo, content: content}, _, _) do
    %{
      __typename: :text_content,
      text: content |> StorageId.from_json() |> Memo.get() |> Utils.trim_text()
    }
    |> ok()
  end

  def fill_content(%{type: type, content: content}, _, _)
      when type in [:file, :image, :video, :audio] do
    {id, secret} = StorageId.from_json(content)
    [_, _, size_str, _, name, _] = Files.get(id, secret)

    %{
      __typename: :file_content,
      initial_name: name,
      size_bytes: String.to_integer(size_str),
      type: type,
      url: WebUtils.get_file_url(type, id, secret)
    }
    |> ok()
  end

  def fill_content(%{type: :room_invite, content: content}, _, _) do
    keys =
      content
      |> StorageId.from_json()
      |> RoomInvites.get()
      |> Identity.from_strings()

    %{
      __typename: :room_invite_content,
      keys: keys
    }
    |> ok()
  end
end
