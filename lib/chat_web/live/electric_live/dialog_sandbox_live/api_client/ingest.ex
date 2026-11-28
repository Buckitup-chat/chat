defmodule ChatWeb.ElectricLive.DialogSandboxLive.ApiClient.Ingest do
  @moduledoc """
  Shared ingest plumbing for the dialog sandbox API client: mutation payloads,
  signing, gated shape results and the gated Electric client.
  """

  import ChatWeb.ElectricLive.SandboxHttp

  alias Chat.Data.Integrity

  @doc "Ingests a single-row insert mutation for `relation`."
  def publish_insert(relation, fields, sign_skey, base_url) do
    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => fields,
          "syncMetadata" => %{"relation" => relation}
        }
      ]
    }

    case ingest(payload, sign_skey, base_url) do
      {:ok, _body, logs} -> {:ok, %{log_entries: logs}}
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  @doc "Builds an update mutation payload for `relation`."
  def update_payload(relation, original, changes) do
    %{
      "mutations" => [
        %{
          "type" => "update",
          "original" => original,
          "changes" => changes,
          "syncMetadata" => %{"relation" => relation}
        }
      ]
    }
  end

  @doc "Wraps a gated shape read into `{:ok, %{key => rows, log_entries: logs}}` or an error map."
  def wrap_gated_result({:ok, rows, logs}, key), do: {:ok, %{key => rows, log_entries: logs}}

  def wrap_gated_result({:error, reason, logs}, _key),
    do: {:error, %{reason: reason, log_entries: logs}}

  @doc "Electric client whose fetches go through the read-session gate."
  def gated_client(base_url, %{user_hash: user_hash, sign_skey: sign_skey}) do
    Electric.Client.new!(
      endpoint: base_url <> "/electric/v1/shapes",
      fetch:
        {ChatWeb.ElectricLive.SandboxGatedFetch,
         base_url: base_url, user_hash: user_hash, sign_skey: sign_skey}
    )
  end

  @doc "Signs the integrity payload of `struct`."
  def sign(struct, sign_skey) do
    struct
    |> Integrity.signature_payload()
    |> EnigmaPq.sign(sign_skey)
  end
end
