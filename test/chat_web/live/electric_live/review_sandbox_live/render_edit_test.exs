defmodule ChatWeb.ElectricLive.ReviewSandboxLive.RenderEditTest do
  @moduledoc "The edit lock the review sandbox applies per moderation mode."
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Chat.Data.Types.ReviewPasswordSignHash
  alias ChatWeb.ElectricLive.ReviewSandboxLive.RenderEdit

  defp actions(mode, proofs) do
    render_component(&RenderEdit.render_review_actions/1,
      moderation_mode: mode,
      observed_proofs: proofs
    )
  end

  defp promoted do
    %{
      review_password_sign_hash:
        :crypto.strong_rand_bytes(64) |> ReviewPasswordSignHash.from_binary(),
      post_right_sign_hash: nil,
      revoke_right_sign_hash: nil
    }
  end

  defp pending do
    %{review_password_sign_hash: nil, post_right_sign_hash: nil, revoke_right_sign_hash: nil}
  end

  test "offers the edit button before any proof has been observed" do
    html = actions(:none, nil)

    assert html =~ "Edit Review"
    refute html =~ "Locked"
  end

  test "post mode stays editable once the password is public" do
    html = actions(:post, promoted())

    assert html =~ "Edit Review"
    refute html =~ "Locked"
  end

  test "pre mode stays editable while the origin has not decided" do
    html = actions(:pre, pending())

    assert html =~ "Edit Review"
    refute html =~ "Locked"
  end

  test "pre mode locks the review once the origin has moderated it" do
    html = actions(:pre, promoted())

    refute html =~ "Edit Review"
    assert html =~ "Locked"
  end

  test "always offers a fresh review" do
    assert actions(:pre, promoted()) =~ "New Review"
    assert actions(:none, nil) =~ "New Review"
  end

  describe "review picker" do
    defp openable(hash, rating, text, ts) do
      %{
        review_hash: hash,
        owner_timestamp: ts,
        review: %{review_hash: hash, rating: rating, text: text},
        entry: %{},
        error: nil
      }
    end

    defp orphan(hash, ts) do
      %{
        review_hash: hash,
        owner_timestamp: ts,
        review: nil,
        entry: nil,
        error: "no review_list row — this review's password is not recoverable"
      }
    end

    defp picker(reviews, selected) do
      render_component(&RenderEdit.render_review_picker/1, reviews: reviews, review: selected)
    end

    test "lists every review on the origin, not just the newest" do
      a = openable("rv_aaaaaaaa", 5, "first", 1)
      b = openable("rv_bbbbbbbb", 3, "second", 2)

      html = picker([b, a], a.review)

      assert html =~ "rv_aaaaaa"
      assert html =~ "rv_bbbbbb"
      assert html =~ "first"
      assert html =~ "second"
      assert html =~ "Your reviews on this origin (2)"
    end

    test "marks the open one and offers to open the others" do
      a = openable("rv_aaaaaaaa", 5, "first", 1)
      b = openable("rv_bbbbbbbb", 3, "second", 2)

      html = picker([b, a], a.review)

      assert html =~ "select_review"
      assert html =~ ~s(phx-value-hash="rv_bbbbbbbb")
      refute html =~ ~s(phx-value-hash="rv_aaaaaaaa")
    end

    test "shows a review that cannot be reopened, with the reason and no button" do
      a = openable("rv_aaaaaaaa", 5, "first", 1)
      lost = orphan("rv_cccccccc", 3)

      html = picker([lost, a], a.review)

      assert html =~ "rv_cccccc"
      assert html =~ "password is not recoverable"
      refute html =~ ~s(phx-value-hash="rv_cccccccc")
    end

    test "renders with nothing selected" do
      html = picker([openable("rv_aaaaaaaa", 5, "first", 1)], nil)

      assert html =~ "rv_aaaaaa"
      assert html =~ ~s(phx-value-hash="rv_aaaaaaaa")
    end
  end
end
