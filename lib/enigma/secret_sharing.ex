defmodule Enigma.SecretSharing do
  @moduledoc """
  Shamir's Secret Sharing
  """

  @doc """
  Generates random shares out of given secret. The total amount of shares should be no more than 255.
  Threshold is a property, that indicates how many of the shares should be enough for restoring the secret.
  Threshold must be smaller than total amount.
  """
  def hide_secret_in_shares(secret, amount, threshold) do
    cond do
      not is_binary(secret) ->
        raise(ArgumentError, message: "secret should be a binary")

      amount < 2 or amount > 255 ->
        raise(ArgumentError,
          message: "amount should be a number between 1 and 256, bounds not included"
        )

      threshold > amount ->
        raise(ArgumentError, message: "amount of shares should be bigger than threshold")

      true ->
        generate_shares(secret, amount, threshold)
    end
  end

  def recover_secret_from_shares(shares), do: KeyX.recover_secret!(shares)

  defp generate_shares(secret, amount, threshold) do
    KeyX.generate_shares!(threshold, 255, secret)
    |> Enum.shuffle()
    |> Enum.reduce_while([], fn share, acc ->
      if length(acc) < amount, do: {:cont, [share | acc]}, else: {:halt, acc}
    end)
  end
end
