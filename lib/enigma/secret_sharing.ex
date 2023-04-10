defmodule Enigma.SecretSharing do
  @moduledoc """
  Shamir's Secret Sharing
  """
  defguard amount_constraint(amount) when amount > 1 and amount < 256
  defguard secret_constraint(secret) when is_binary(secret) and byte_size(secret) == 32
  defguard threshold_constraint(threshold, amount) when threshold <= amount

  defguard constraints(secret, amount, threshold)
           when amount_constraint(amount) and secret_constraint(secret) and
                  threshold_constraint(threshold, amount)

  @doc """
  Generates random shares out of given secret. The total amount of shares should be no more than 255.
  Threshold is a property, that indicates how many of the shares should be enough for restoring the secret.
  Threshold must be smaller than total amount.
  """
  def hide_secret_in_shares(secret, amount, threshold)
      when constraints(secret, amount, threshold) do
    KeyX.generate_shares!(threshold, 255, secret)
    |> Enum.shuffle()
    |> Enum.reduce_while([], fn share, acc ->
      if length(acc) < amount, do: {:cont, [share | acc]}, else: {:halt, acc}
    end)
  end

  def hide_secret_in_shares(secret, _amount, _threshold) when not secret_constraint(secret),
    do: raise(ArgumentError, message: "byte_size of secret (which should be binary string) should be 32")

  def hide_secret_in_shares(_secret, amount, _threshold) when not amount_constraint(amount),
    do:
      raise(ArgumentError,
        message: "amount should be a number between 1 and 256, bounds not included"
      )

  def hide_secret_in_shares(_secret, amount, threshold) when not threshold_constraint(threshold, amount),
    do: raise(ArgumentError, message: "threshold should be no more than amount")

  def recover_secret_from_shares(shares), do: KeyX.recover_secret!(shares)
end
