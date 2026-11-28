defmodule ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.Fetch do
  @moduledoc """
  Gated shape reads for dialog sandbox data: user cards, dialog keys, messages,
  versions, reactions and receipts.
  """

  import ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.Ingest, only: [wrap_gated_result: 2]

  alias ChatWeb.ElectricLive.SandboxHttp

  def fetch_all_user_cards(base_url, auth) do
    base_url |> SandboxHttp.fetch_shape_gated("user_cards", auth) |> wrap_gated_result(:cards)
  end

  def fetch_user_card(user_hash, base_url, auth) do
    case SandboxHttp.fetch_shape_gated(base_url, "user_cards", "user_hash='#{user_hash}'", auth) do
      {:ok, rows, logs} ->
        {:ok, %{card: List.first(rows), log_entries: logs}}

      {:error, reason, logs} ->
        {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def fetch_dialog_keys(user_hash, base_url, auth) do
    with {:ok, sender_rows, logs1} <-
           SandboxHttp.fetch_shape_gated(
             base_url,
             "dialog_keys",
             "sender_hash::text='#{user_hash}'",
             auth
           ),
         {:ok, peer_rows, logs2} <-
           SandboxHttp.fetch_shape_gated(
             base_url,
             "dialog_keys",
             "peer_hash='#{user_hash}'",
             auth
           ) do
      all_keys =
        (sender_rows ++ peer_rows)
        |> Enum.uniq_by(&{&1["dialog_hash"], &1["sender_hash"]})

      {:ok, %{keys: all_keys, log_entries: logs1 ++ logs2}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def fetch_dialog_keys_by_dialog(dialog_hash, base_url, auth) do
    base_url
    |> SandboxHttp.fetch_shape_gated("dialog_keys", "dialog_hash='#{dialog_hash}'", auth)
    |> wrap_gated_result(:keys)
  end

  def fetch_dialog_messages(dialog_hash, base_url, auth) do
    base_url
    |> SandboxHttp.fetch_shape_gated(
      "dialog_messages",
      "dialog_hash='#{dialog_hash}'",
      auth
    )
    |> wrap_gated_result(:messages)
  end

  def fetch_message_versions(message_id, base_url, auth) do
    base_url
    |> SandboxHttp.fetch_shape_gated(
      "dialog_messages_versions",
      "message_id='#{message_id}'",
      auth
    )
    |> wrap_gated_result(:versions)
  end

  def fetch_reactions(dialog_hash, base_url, auth) do
    base_url
    |> SandboxHttp.fetch_shape_gated(
      "dialog_message_reactions",
      "dialog_hash='#{dialog_hash}'",
      auth
    )
    |> wrap_gated_result(:reactions)
  end

  def fetch_receipts(dialog_hash, base_url, auth) do
    base_url
    |> SandboxHttp.fetch_shape_gated(
      "dialog_message_receipts",
      "dialog_hash='#{dialog_hash}'",
      auth
    )
    |> wrap_gated_result(:receipts)
  end
end
