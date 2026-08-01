defmodule ChatWeb.ElectricLive.ReviewContent do
  @moduledoc false

  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto

  def decode(content_b64, password) do
    with content when is_binary(content) <- Crypto.decode_binary_field(content_b64),
         plaintext when is_binary(plaintext) <- EnigmaPq.aes_gcm_decrypt(content, password),
         {:ok, [rating, _placeholder, text]} <- Jason.decode(plaintext) do
      {:ok, %{rating: rating, text: text}}
    else
      _ -> :error
    end
  end
end
