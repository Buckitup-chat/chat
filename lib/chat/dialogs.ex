defmodule Chat.Dialogs do
  @moduledoc "Context for dialogs"

  alias Chat.Card
  alias Chat.Dialogs.Dialog
  alias Chat.Dialogs.Registry
  alias Chat.Identity

  def find_or_open(%Identity{} = src, %Card{} = dst) do
    case Registry.find(src, dst) do
      nil ->
        open(src, dst)
        |> tap(&update/1)

      dialog ->
        dialog
    end
  end

  def open(%Identity{} = src, %Card{} = dst) do
    Dialog.start(src, dst)
  end

  defdelegate update(dialog), to: Registry

  defdelegate add_text(dialog, src, text, now \\ DateTime.utc_now()), to: Dialog
  defdelegate add_image(dialog, src, data, now \\ DateTime.utc_now()), to: Dialog

  defdelegate glimpse(dialog), to: Dialog

  defdelegate read(
                dialog,
                reader,
                before \\ DateTime.utc_now() |> DateTime.add(1) |> DateTime.to_unix(),
                amount \\ 1000
              ),
              to: Dialog
end
