defmodule ChatWeb.ElectricLive.ReviewSandboxLive.RenderVerification do
  @moduledoc false

  use Phoenix.Component

  def render_verification_results(assigns) do
    ~H"""
    <div class="space-y-3 mt-3">
      <%= if @verification.revoke do %>
        {render_candidate_check(
          %{label: "Revoke", result: @verification.revoke, type: :revoke}
          |> Map.merge(Map.take(assigns, [:review]))
        )}
      <% end %>
      <%= if @verification.post do %>
        {render_candidate_check(
          %{label: "Post", result: @verification.post, type: :post}
          |> Map.merge(Map.take(assigns, [:review]))
        )}
      <% end %>
    </div>
    """
  end

  defp render_candidate_check(assigns) do
    ~H"""
    <div class={"border rounded p-3 text-xs #{if @result.status == :ok, do: "border-green-300 bg-green-50", else: "border-red-300 bg-red-50"}"}>
      <p class="font-semibold mb-2">{@label} right — wrapping verification</p>
      <%= if @result.unwrapped do %>
        <div class="space-y-1 font-mono">
          {check_line("AES-GCM decryption", :ok)}
          {check_line(
            "review_hash",
            if(@result.unwrapped["review_hash"] == @review.review_hash, do: :ok, else: :fail)
          )}
          {check_line(
            "password_b64 #{if @type == :revoke, do: "is null", else: "matches"}",
            password_check(@result.unwrapped["password_b64"], @type, @review)
          )}
        </div>
        <details class="mt-2">
          <summary class="cursor-pointer text-gray-600">Unwrapped content</summary>
          <pre class="mt-1 whitespace-pre-wrap overflow-x-auto bg-white p-2 rounded">{Jason.encode!(@result.unwrapped, pretty: true)}</pre>
        </details>
      <% else %>
        <div class="font-mono">
          {check_line("AES-GCM decryption", :fail)}
        </div>
        <p class="mt-1 text-red-700">{elem(@result.status, 1)}</p>
      <% end %>
    </div>
    """
  end

  defp check_line(label, status) do
    assigns = %{label: label, status: status}

    ~H"""
    <p>
      <span class={if @status == :ok, do: "text-green-700", else: "text-red-700"}>
        {if @status == :ok, do: "pass", else: "FAIL"}
      </span>
      <span class="text-gray-700 ml-1">{@label}</span>
    </p>
    """
  end

  defp password_check(password_b64, :revoke, _review) do
    if password_b64 == nil, do: :ok, else: :fail
  end

  defp password_check(password_b64, :post, review) do
    expected = Base.encode64(review.review_password, padding: false)
    if password_b64 == expected, do: :ok, else: :fail
  end
end
