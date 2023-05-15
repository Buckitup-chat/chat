defmodule Chat.KeyShare do
  @moduledoc "Manipulate social sharing keys"

  alias Chat.{Dialogs, Dialogs.Dialog, Identity, User.Registry}
  alias Chat.{ChunkedFiles, ChunkedFilesMultisecret}
  alias Chat.Upload.UploadKey

  alias Ecto.Changeset

  alias Combinatorics

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
    |> content_result()
  end

  def content_result(result),
    do: if(result |> Enum.any?(&(&1 == :error)), do: :error, else: result)

  def decode_content(content) do
    case content |> Base.decode64() do
      {:ok, element} -> element
      _ -> :error
    end
  end

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

  def filter_out_broken(shares) when is_list(shares) and length(shares) > @threshold do
    max_try = shares |> Enum.count() |> Kernel.-(@threshold)

    broken_shares = keystring_selection(shares, max_try)

    shares
    |> Enum.map(fn share ->
      if share in broken_shares, do: Map.put_new(share, :broken, true), else: share
    end)
  end

  def filter_out_broken(shares), do: shares

  def broken?(share), do: Map.has_key?(share, :broken)

  def keystring_selection(shares, 1 = _tries), do: run_selection(shares, 1)

  def keystring_selection(shares, tries) do
    Enum.reduce_while(1..tries, [], fn try_number, _acc ->
      case run_selection(shares, try_number) do
        [] -> {:cont, []}
        [_ | _] = shares -> {:halt, shares}
      end
    end)
  end

  def client_name(%Identity{name: name, public_key: pub_key} = _me),
    do: "This is my ID #{name}-#{Enigma.short_hash(pub_key)}.social_part"

  defp run_selection(shares, try_number) do
    try_number
    |> Combinatorics.n_combinations(shares)
    |> Enum.reduce_while([], fn share, acc ->
      with keypair <- build_keypair_without({shares, share}),
           user_from_share <- user_in_share(keypair) do
        case user_from_share do
          :user_keystring_broken ->
            {:cont, []}

          {:ok, _user} ->
            {:halt, acc ++ share}
        end
      end
    end)
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

  defp save({file_key, share_key}, {file_size, file_secret}) do
    ChunkedFilesMultisecret.generate(file_key, file_size, file_secret)
    ChunkedFiles.save_upload_chunk(file_key, {0, file_size - 1}, file_size, share_key)
  end

  defp encode_content({key, hash}),
    do: Base.encode64(key) <> "\n" <> Base.encode64(hash)

  defp build_keypair_without({shares, exclude}) do
    shares
    |> Kernel.--(exclude_check_list(exclude))
    |> Enum.map(&Map.get(&1, :key))
    |> Enigma.recover_secret_from_shares()
  end

  defp exclude_check_list(exclude) when is_list(exclude), do: exclude
  defp exclude_check_list(exclude), do: [exclude]
end
