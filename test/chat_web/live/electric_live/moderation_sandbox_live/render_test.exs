defmodule ChatWeb.ElectricLive.ModerationSandboxLive.RenderTest do
  @moduledoc "Queue rendering: state badges, readable content and action availability."
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias ChatWeb.ElectricLive.ModerationSandboxLive.Render

  describe "render_queue_section/1" do
    test "pending review with both rights offers publish and reject" do
      html =
        queue_html([
          entry(state: :pending, post_right: unwrapped(200), revoke_right: unwrapped(201))
        ])

      assert html =~ "Pending"
      assert html =~ "great coffee"
      assert buttons(html) == %{"Publish" => :enabled, "Reject" => :enabled}
    end

    test "public review offers revoke only" do
      html = queue_html([entry(state: :public, revoke_right: unwrapped(201))])

      assert html =~ "Public"
      assert buttons(html) == %{"Revoke" => :enabled}
    end

    test "hidden review disables a post right that cannot supersede the revoke" do
      html =
        queue_html([entry(state: :hidden, post_right: unwrapped(200), publish_effective?: false)])

      assert html =~ "Hidden"
      assert buttons(html) == %{"Re-publish" => :disabled}
      assert html =~ "publish blocked"
    end

    test "locked review reports why it cannot be read" do
      html = queue_html([entry(rating: nil, text: nil, content_error: :no_password)])

      assert html =~ "no password available"
      assert html =~ "author has not completed the moderation handshake"
      assert buttons(html) == %{}
    end

    test "unusable envelope surfaces the decryption failure" do
      failed = %{status: :error, row: nil, owner_timestamp: nil, reason: "decryption failed"}
      html = queue_html([entry(post_right: failed)])

      assert html =~ "decryption failed"
      assert buttons(html) == %{"Publish" => :disabled}
    end

    test "empty queue points to the review sandbox" do
      assert queue_html([]) =~ "No reviews for this origin yet"
    end
  end

  # Helpers

  defp queue_html(entries) do
    %{entries: entries, loading: false, counts: nil}
    |> Render.render_queue_section()
    |> rendered_to_string()
  end

  defp buttons(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("button[phx-click='publish'], button[phx-click='revoke']")
    |> Map.new(fn button ->
      state = if Floki.attribute(button, "disabled") == [], do: :enabled, else: :disabled

      {button |> Floki.text() |> String.trim(), state}
    end)
  end

  defp entry(overrides) do
    %{
      review_hash: "rv_" <> String.duplicate("c", 128),
      author_hash: "u_" <> String.duplicate("b", 128),
      owner_timestamp: 100,
      state: :pending,
      latest_timestamp: nil,
      post_right: nil,
      revoke_right: nil,
      password_source: :post_right,
      rating: 5,
      text: "great coffee",
      content_error: nil,
      publish_effective?: true,
      revoke_effective?: true
    }
    |> Map.merge(Map.new(overrides))
  end

  defp unwrapped(timestamp) do
    %{
      status: :ok,
      row: %{"owner_timestamp" => timestamp},
      owner_timestamp: timestamp,
      reason: nil
    }
  end
end
