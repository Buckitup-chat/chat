defmodule Chat.Admin.CargoSettings do
  @moduledoc """
  Defines cargo settings form data structure and handles validation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:checkpoints, {:array, :string}, default: [])
  end

  def changeset(%__MODULE__{} = cargo_settings, attrs) do
    cargo_settings
    |> cast(attrs, [:checkpoints])
    |> validate_required([:checkpoints])
  end
end
