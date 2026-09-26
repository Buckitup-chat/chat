defmodule ChatWeb.ElectricLive.IdentityCheck do
  @moduledoc """
  Flags an imported identity whose user card is not on this server.

  Every ingest is authorised against the issuer's `user_cards` row, so without it
  all writes fail with an opaque 400 "Invalid operation". The flag lives on the
  identity map (`:on_server`) so sandboxes need no extra assigns.
  """

  alias Electric.Client
  alias ChatWeb.ElectricLive.ShapeReader

  def mark_on_server(identity, base_url) do
    Map.put(identity, :on_server, card_on_server?(identity.user_hash, base_url))
  end

  defp card_on_server?(user_hash, base_url) do
    shape =
      Client.ShapeDefinition.new!("user_cards",
        where: "user_hash = $1",
        params: [user_hash],
        columns: ~w(user_hash deleted_flag)
      )

    Client.new!(endpoint: base_url <> "/electric/v1/shapes")
    |> ShapeReader.collect(shape)
    |> Enum.any?(&(&1["deleted_flag"] not in [true, "true", "t"]))
  end
end
