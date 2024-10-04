defmodule Chat.Admin.BackupSettings do
  @moduledoc """
  Defines backup settings form data structure and handles validation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:type, Ecto.Enum,
      default: :regular,
      values: [regular: "Regular", continuous: "Continuous"]
    )
  end

  def changeset(%__MODULE__{} = backup_settings, attrs) do
    backup_settings
    |> cast(attrs, [:type])
    |> validate_required([:type])
  end
end
