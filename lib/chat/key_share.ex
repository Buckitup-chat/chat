defmodule Chat.KeyShare do
  @moduledoc "Manipulate social sharing keys"

  alias Chat.{Dialogs, Dialogs.Dialog, Identity, User.Registry}
  alias Chat.{ChunkedFiles, ChunkedFilesMultisecret}
  alias Chat.Upload.UploadKey

  alias Ecto.Changeset

  @threshold 4

  def threshold, do: @threshold

  def generate_key_shares({%Identity{private_key: private_key} = me, users}) do
    amount = Enum.count(users)
    hash = private_key |> Enigma.hash() |> Enigma.sign(private_key)

    me
    |> Identity.to_strings()
    |> Enum.at(1)
    |> Enigma.hide_secret_in_shares(amount, @threshold)
    |> Enum.zip_reduce(users, [], fn key, user, acc ->
      acc ++
        [
          %{
            user: user,
            key: {key, hash} |> encode_content()
          }
        ]
    end)
  end

  def save_shares(shares, {me, time_offset}) do
    shares
    |> Enum.map(fn share ->
      with dialog <- Dialogs.find_or_open(me, share.user),
           file_info <- %{
             size: byte_size(share.key),
             time: Chat.Time.monotonic_to_unix(time_offset)
           },
           entry <- entry(file_info, me),
           destination <- destination(dialog),
           file_key <- UploadKey.new(destination, dialog.b_key, entry),
           file_secret <- ChunkedFiles.new_upload(file_key),
           :ok <- save({file_key, share.key}, {file_info.size, file_secret}) do
        %{
          entry: entry,
          dialog: dialog,
          me: me,
          file_info: {file_key, file_secret, file_info.time},
          size: file_info.size,
          key: share.key
        }
      end
    end)
  end

  def compose([], upload_shares), do: MapSet.new(upload_shares)

  def compose(shares, upload_shares) do
    MapSet.union(MapSet.new(shares), MapSet.new(upload_shares))
  end

  def look_for_duplicates(shares) do
    shares
    |> Enum.group_by(& &1.key)
    |> Enum.filter(&duplicated_share?/1)
    |> Enum.map(fn {key, maps} ->
      %{
        key: key,
        exclude: maps |> Enum.min_by(&(&1.ref |> String.to_integer())) |> Map.get(:ref),
        ref: Enum.map(maps, & &1.ref)
      }
    end)
  end

  def read_content(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim_trailing/1)
    |> Enum.map(&decode_content/1)
  end

  def decode_content(content), do: content |> Base.decode64() |> elem(1)

  def user_in_share(keystring) do
    case keystring |> Base.decode64() do
      {:ok, <<_private::binary-size(32), public::binary-size(33)>>} ->
        {_, user} =
          Registry.all()
          |> Enum.find(fn {_, user} ->
            user.pub_key == public
          end)

        {:ok, user}

      :error ->
        :user_keystring_broken
    end
  end

  def check(params) do
    {%{}, schema()}
    |> Changeset.cast(params, schema() |> Map.keys())
    |> Changeset.validate_required(:shares)
    |> Changeset.validate_length(:shares, min: @threshold)
    |> validate_user_hash()
    |> validate_unique()
    |> Map.put(:action, :validate)
  end

  def changeset, do: Changeset.change({%{}, schema()})

  def schema, do: %{shares: {:array, :map}}

  def validate_unique(%Changeset{changes: %{shares: []}} = changeset), do: changeset

  def validate_unique(%Changeset{changes: %{shares: shares}} = changeset) do
    duplicates = shares |> look_for_duplicates()

    case duplicates do
      [] ->
        changeset

      _ ->
        Changeset.add_error(
          changeset,
          :shares,
          "duplicates are found: #{Enum.map(duplicates, & &1.ref)}"
        )
    end
  end

  def validate_user_hash(%Changeset{changes: %{shares: []}} = changeset), do: changeset

  def validate_user_hash(%Changeset{changes: %{shares: shares}} = changeset) do
    case Enum.all?(shares, fn share -> share.valid end) do
      true ->
        changeset

      false ->
        Changeset.add_error(
          changeset,
          :shares,
          "mismatch: different user file"
        )
    end
  end

  defp duplicated_share?({_key, shares}), do: match?([_, _ | _], shares)

  defp destination(%Dialog{b_key: b_key} = dialog) do
    %{
      dialog: dialog,
      pub_key: Base.encode16(b_key, case: :lower),
      type: :dialog
    }
  end

  defp entry(file_info, me) do
    %{
      client_last_modified: file_info.time,
      client_name: me |> client_name(),
      client_relative_path: nil,
      client_size: file_info.size,
      client_type: "text/plain"
    }
  end

  defp client_name(%Identity{name: name, public_key: pub_key} = _me),
    do: "This is my ID #{name}-#{Enigma.short_hash(pub_key)}.social_part"

  defp save({file_key, share_key}, {file_size, file_secret}) do
    ChunkedFilesMultisecret.generate(file_key, file_size, file_secret)
    ChunkedFiles.save_upload_chunk(file_key, {0, file_size - 1}, file_size, share_key)
  end

  defp encode_content({key, hash}),
    do: Base.encode64(key) <> "\n" <> Base.encode64(hash)
end
