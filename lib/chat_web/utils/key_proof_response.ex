defmodule ChatWeb.Utils.KeyProofResponse do
  @moduledoc "HTTP status and body for a refused `Chat.Pq.KeyProof.prove/3`."

  def of(:invalid_challenge), do: {401, %{error: "Invalid or expired challenge"}}
  def of(:unknown_user), do: {401, %{error: "unknown_user"}}
  def of(:invalid_signature), do: {401, %{error: "invalid_signature"}}
end
