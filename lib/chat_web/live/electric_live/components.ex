defmodule ChatWeb.ElectricLive.Components do
  @moduledoc false

  use Phoenix.Component

  attr :rating, :integer, required: true

  def stars(assigns) do
    ~H"""
    <div class="flex gap-0.5">
      <span :for={i <- 1..5} class={if i <= @rating, do: "text-yellow-400", else: "text-gray-300"}>
        &#9733;
      </span>
    </div>
    """
  end

  attr :identity, :map, required: true

  @doc "Warns when the imported identity has no user card on this server."
  def identity_not_on_server(assigns) do
    ~H"""
    <div
      :if={Map.get(@identity, :on_server) == false}
      class="t-identity-not-on-server mt-3 bg-yellow-50 border border-yellow-300 text-yellow-900 px-4 py-3 rounded text-sm"
    >
      <p class="font-medium">This user is not on this server.</p>
      <p class="mt-1">
        Every write will be rejected ("Invalid operation"). Import the same key file in
        <a href="/electric/user_sandbox" class="text-blue-600 hover:underline">User Sandbox</a>
        to publish the user card, then re-import it here.
      </p>
    </div>
    """
  end
end
