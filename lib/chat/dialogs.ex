defmodule Chat.Dialogs do
  @moduledoc "Context for dialogs"

  alias Chat.Dialogs.Dialog
  alias Chat.Dialogs.Registry
  alias Chat.User

  def find_or_open(%User.Identity{} = src, %User.Card{} = dst) do
    case Registry.find(src, dst) do
      nil ->
        open(src, dst)
        |> tap(&update/1)

      dialog ->
        dialog
    end
  end

  def open(%User.Identity{} = src, %User.Card{} = dst) do
    Dialog.start(src, dst)
  end

  defdelegate update(dialog), to: Registry

  defdelegate add_text(dialog, src, text, now \\ DateTime.utc_now()), to: Dialog

  defdelegate glimpse(dialog), to: Dialog

  defdelegate read(
                dialog,
                reader,
                before \\ DateTime.utc_now() |> DateTime.add(1) |> DateTime.to_unix(),
                amount \\ 1000
              ),
              to: Dialog
end
