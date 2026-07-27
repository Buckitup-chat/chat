defmodule ChatWeb.ElectricLive.ReviewSandboxLive.Verification do
  @moduledoc "Verifies server-wrapped right candidates before author signs them."

  import ChatWeb.ElectricLive.ReviewSandboxLive.Http, only: [encode_base64: 1]

  alias Chat.Data.ReviewRightEnvelope
  alias EnigmaPq

  def extract_shared_secrets(%{headers: headers}) do
    %{}
    |> put_decoded_header(headers, "x-review-post-shared-secret", :post_shared_secret)
    |> put_decoded_header(headers, "x-review-revoke-shared-secret", :revoke_shared_secret)
  end

  def verify_candidates(candidates, shared_secrets, review, author) do
    results = %{
      post:
        unwrap_and_check(
          candidates.post,
          shared_secrets[:post_shared_secret],
          review,
          author,
          :post
        ),
      revoke:
        unwrap_and_check(
          candidates.revoke,
          shared_secrets[:revoke_shared_secret],
          review,
          author,
          :revoke
        )
    }

    all_ok =
      [results.post, results.revoke]
      |> Enum.reject(&is_nil/1)
      |> Enum.all?(&(&1.status == :ok))

    Map.put(results, :all_ok, all_ok)
  end

  def verify_wrapping(candidates, shared_secrets, review, author) do
    with :ok <-
           check_candidate(
             candidates.post,
             shared_secrets[:post_shared_secret],
             review,
             author,
             :post
           ),
         :ok <-
           check_candidate(
             candidates.revoke,
             shared_secrets[:revoke_shared_secret],
             review,
             author,
             :revoke
           ) do
      :ok
    end
  end

  defp put_decoded_header(acc, headers, name, key) do
    case headers do
      %{^name => [value | _]} -> Map.put(acc, key, Base.decode64!(value, padding: false))
      _ -> acc
    end
  end

  defp unwrap_and_check(nil, _secret, _review, _author, _type), do: nil

  defp unwrap_and_check(_candidate, nil, _review, _author, _type),
    do: %{status: {:error, "missing shared secret"}, unwrapped: nil}

  defp unwrap_and_check(candidate, shared_secret, review, author, type) do
    case decrypt_wrapped(candidate.wrapped_row_b64, shared_secret) do
      :error ->
        %{status: {:error, "decryption failed — server may have tampered"}, unwrapped: nil}

      row ->
        %{status: verify_row_fields(row, review, author, type), unwrapped: row}
    end
  end

  defp check_candidate(nil, _secret, _review, _author, _type), do: :ok

  defp check_candidate(_candidate, nil, _review, _author, _type),
    do: {:error, "missing shared secret for right candidate verification"}

  defp check_candidate(candidate, shared_secret, review, author, type) do
    case decrypt_wrapped(candidate.wrapped_row_b64, shared_secret) do
      :error -> {:error, "wrapped content decryption failed — server may have tampered"}
      row -> verify_row_fields(row, review, author, type)
    end
  end

  defp decrypt_wrapped(wrapped_b64, shared_secret) do
    wrap_key = ReviewRightEnvelope.wrap_key(shared_secret)

    case EnigmaPq.aes_gcm_decrypt(wrapped_b64, wrap_key) do
      :error -> :error
      row_json -> Jason.decode!(row_json)
    end
  end

  defp verify_row_fields(row, review, author, type) do
    cond do
      row["review_hash"] != review.review_hash ->
        {:error, "wrapped review_hash does not match submitted review"}

      row["author_hash"] != author.user_hash ->
        {:error, "wrapped author_hash does not match author identity"}

      type == :revoke and row["password_b64"] != nil ->
        {:error, "revoke right wraps non-null password"}

      type == :post and row["password_b64"] != encode_base64(review.review_password) ->
        {:error, "post right password does not match review password"}

      true ->
        :ok
    end
  end
end
