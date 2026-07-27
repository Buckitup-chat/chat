defmodule ChatWeb.ElectricLive.ModerationSandboxLive.ApiClient do
  @moduledoc """
  Moderation actions over the Electric ingest endpoint.

  The origin identity never signs a `review_public_passwords` row: it submits
  the author's pre-signed row that it just unwrapped from a right envelope. The
  only thing the origin signs is the ingest challenge, which is what authorizes
  the write as the origin identity.
  """

  import ChatWeb.ElectricLive.ReviewSandboxLive.Http, only: [get_challenge: 1, post_ingest: 4]

  @doc "Submits an unwrapped, author-signed review_public_passwords row."
  def moderate(identity, %{status: :ok, row: row}, base_url) do
    payload = %{
      "mutations" => [
        %{
          "type" => "insert",
          "modified" => row,
          "syncMetadata" => %{"relation" => "review_public_passwords"}
        }
      ]
    }

    with {:ok, challenge, log1} <- get_challenge(base_url),
         {:ok, _resp, log2} <- post_ingest(challenge, payload, identity.sign_skey, base_url) do
      {:ok, %{log_entries: [log1, log2]}}
    else
      {:error, reason, logs} -> {:error, %{reason: reason, log_entries: logs}}
    end
  end

  def moderate(_identity, _right, _base_url),
    do: {:error, %{reason: "no usable right envelope for this review", log_entries: []}}
end
