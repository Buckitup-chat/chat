defmodule ChatWeb.ElectricLive.ReviewSandboxLive.RenderReviewListTest do
  @moduledoc """
  Renders the step-5 section in each state it can reach.

  The page-level test never gets here — step 5 only appears once an identity is
  imported and the moderation pipeline has run, which needs live HTTP that
  `server: false` forbids. So the states are driven directly.
  """
  use ExUnit.Case, async: true

  import ChatWeb.ElectricLive.ReviewSandboxLive.RenderReviewList
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  @password "rvps_aaa"
  @post "rvprs_bbb"
  @revoke "rvrrs_ccc"

  @local %{
    review_password_sign_hash: @password,
    post_right_sign_hash: @post,
    revoke_right_sign_hash: @revoke
  }

  test "before proofs are loaded it offers to load them and blocks submission" do
    html = render(moderation_mode: :none, observed_proofs: nil)

    assert html =~ "Step 5: Add to Review List"
    assert html =~ "Load proofs"
    assert html =~ "Add to Review List"
    assert html =~ "cursor-not-allowed"
  end

  test "an observed matching proof enables submission" do
    html = render(moderation_mode: :none, observed_proofs: observed(password: @password))

    assert html =~ "Refresh"
    refute html =~ "cursor-not-allowed"
  end

  test "a mismatched promotion row says so and blocks" do
    html = render(moderation_mode: :none, observed_proofs: observed(password: "rvps_other"))

    assert html =~ "differs from what you signed"
    assert html =~ "cursor-not-allowed"
  end

  test "pre mode waits for the origin after the row is inserted" do
    html =
      render(
        moderation_mode: :pre,
        observed_proofs: observed(post: @post, revoke: @revoke),
        entry: entry(review_password_sign_hash: nil)
      )

    assert html =~ "the origin has not published yet"
    assert html =~ "Waiting for origin to publish"
  end

  test "pre mode offers the fill-in once the promotion row appears" do
    html =
      render(
        moderation_mode: :pre,
        observed_proofs: observed(password: @password, post: @post, revoke: @revoke),
        entry: entry(review_password_sign_hash: nil)
      )

    assert html =~ "Fill promotion proof"
    refute html =~ "Waiting for origin to publish"
  end

  test "a completed row reports done and offers key delivery" do
    html =
      render(
        moderation_mode: :pre,
        observed_proofs: observed(password: @password, post: @post, revoke: @revoke),
        entry: entry(review_password_sign_hash: @password),
        peers: [%{user_hash: "u_peer", name: "Bob"}]
      )

    assert html =~ "Review list row complete"
    assert html =~ "Share the list key"
    assert html =~ "Bob"
  end

  test "key delivery marks peers already sent to" do
    html =
      render(
        moderation_mode: :none,
        observed_proofs: observed(password: @password),
        entry: entry(review_password_sign_hash: @password),
        peers: [%{user_hash: "u_peer", name: "Bob"}],
        key_sent_to: ["u_peer"]
      )

    assert html =~ "sent"
  end

  test "key delivery says so when there is nobody to share with" do
    html =
      render(
        moderation_mode: :none,
        observed_proofs: observed(password: @password),
        entry: entry(review_password_sign_hash: @password)
      )

    assert html =~ "No other users to share with"
  end

  defp render(opts) do
    %{
      moderation_mode: Keyword.fetch!(opts, :moderation_mode),
      observed_proofs: Keyword.get(opts, :observed_proofs),
      proof_hashes: Keyword.get(opts, :proof_hashes, @local),
      review_list: %{entry: Keyword.get(opts, :entry)},
      peers: Keyword.get(opts, :peers, []),
      selected_contacts: Keyword.get(opts, :selected_contacts, []),
      key_sent_to: Keyword.get(opts, :key_sent_to, [])
    }
    |> render_review_list_section()
    |> rendered_to_string()
  end

  defp observed(opts) do
    %{
      review_password_sign_hash: opts[:password],
      post_right_sign_hash: opts[:post],
      revoke_right_sign_hash: opts[:revoke]
    }
  end

  defp entry(opts) do
    %Chat.Data.Schemas.ReviewList{
      user_hash: "u_author",
      review_hash: "rv_one",
      review_password_sign_hash: opts[:review_password_sign_hash]
    }
  end
end
