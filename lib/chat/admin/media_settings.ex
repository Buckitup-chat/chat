defmodule Chat.Admin.MediaSettings do
  @moduledoc """
  Defines media settings form data structure and handles validation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:functionality, Ecto.Enum,
      default: :backup,
      values: [backup: "Backup", cargo: "Cargo", onliners: "Onliners sync"]
    )
  end

  def changeset(%__MODULE__{} = media_settings, attrs) do
    media_settings
    |> cast(attrs, [:functionality])
    |> validate_required([:functionality])
  end
end
