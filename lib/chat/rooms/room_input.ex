defmodule Chat.Rooms.RoomInput do
  @moduledoc """
  Defines room form data structure and handles validation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Chat.Admin.MediaSettings
  alias Chat.Rooms.{Registry, Room}

  @regular_types [:public, :request, :private]

  @primary_key false
  embedded_schema do
    field(:name, :string)

    field(:type, Ecto.Enum,
      default: :public,
      values: [public: "Open", request: "Private", private: "Secret", cargo: "Cargo"]
    )
  end

  def changeset(%__MODULE__{} = input, attrs, media_settings \\ %MediaSettings{}) do
    input
    |> cast(attrs, [:name, :type])
    |> validate_required([:name, :type])
    |> validate_name_uniqueness()
    |> validate_type(media_settings)
  end

  defp validate_name_uniqueness(%Ecto.Changeset{} = changeset) do
    name = get_field(changeset, :name)
    type = get_field(changeset, :type)

    cond do
      type != :cargo ->
        changeset

      unique?(name) ->
        changeset

      true ->
        add_error(changeset, :name, "has already been taken")
    end
  end

  defp unique?(name) do
    Registry.all()
    |> Enum.any?(fn {_room_pub_key, %Room{} = room} ->
      room.name == name
    end)
    |> Kernel.not()
  end

  defp validate_type(%Ecto.Changeset{} = changeset, %MediaSettings{} = media_settings) do
    types =
      case media_settings.functionality do
        :cargo ->
          [:cargo | @regular_types]

        _ ->
          @regular_types
      end

    type = get_field(changeset, :type)

    if type in types do
      changeset
    else
      add_error(changeset, :type, "is invalid")
    end
  end
end
