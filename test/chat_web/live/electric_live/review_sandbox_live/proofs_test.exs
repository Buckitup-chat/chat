defmodule ChatWeb.ElectricLive.ReviewSandboxLive.ReviewList.ProofsTest do
  @moduledoc "The client-side moderation-proof matrix for a review_list row."
  use ExUnit.Case, async: true

  alias ChatWeb.ElectricLive.ReviewSandboxLive.ReviewList.Proofs

  @password "rvps_aaa"
  @post "rvprs_bbb"
  @revoke "rvrrs_ccc"

  @local %{
    review_password_sign_hash: @password,
    post_right_sign_hash: @post,
    revoke_right_sign_hash: @revoke
  }

  describe "requirement/2 mirrors the server matrix" do
    test "none needs only the promotion proof" do
      assert Proofs.requirement(:none, :review_password_sign_hash) == :required
      assert Proofs.requirement(:none, :post_right_sign_hash) == :forbidden
      assert Proofs.requirement(:none, :revoke_right_sign_hash) == :forbidden
    end

    test "post needs promotion and revoke, never post right" do
      assert Proofs.requirement(:post, :review_password_sign_hash) == :required
      assert Proofs.requirement(:post, :post_right_sign_hash) == :forbidden
      assert Proofs.requirement(:post, :revoke_right_sign_hash) == :required
    end

    test "pre needs both rights, promotion only once approved" do
      assert Proofs.requirement(:pre, :review_password_sign_hash) == :optional
      assert Proofs.requirement(:pre, :post_right_sign_hash) == :required
      assert Proofs.requirement(:pre, :revoke_right_sign_hash) == :required
    end
  end

  describe "fields/3" do
    test "none sends the promotion proof alone" do
      status = Proofs.status(:none, observed(password: @password), @local)

      assert Proofs.fields(:none, @local, status) == %{review_password_sign_hash: @password}
    end

    test "post sends promotion and revoke, dropping the forbidden post right" do
      observed = observed(password: @password, revoke: @revoke)
      status = Proofs.status(:post, observed, @local)

      assert Proofs.fields(:post, @local, status) == %{
               review_password_sign_hash: @password,
               revoke_right_sign_hash: @revoke
             }
    end

    # The author holds the promotion hash from the moment they sign the
    # candidate, but until the origin publishes there is no row to point at and
    # optional_password_proof/3 would reject it.
    test "pre omits the promotion proof until the origin has published" do
      observed = observed(post: @post, revoke: @revoke)
      status = Proofs.status(:pre, observed, @local)

      assert Proofs.fields(:pre, @local, status) == %{
               post_right_sign_hash: @post,
               revoke_right_sign_hash: @revoke
             }
    end

    test "pre includes the promotion proof once it is observed" do
      observed = observed(password: @password, post: @post, revoke: @revoke)
      status = Proofs.status(:pre, observed, @local)

      assert Proofs.fields(:pre, @local, status)[:review_password_sign_hash] == @password
    end
  end

  describe "status/3" do
    test "an unobserved required proof is pending, not a failure" do
      status = Proofs.status(:none, observed([]), @local)

      assert status.review_password_sign_hash == :pending
      assert Proofs.submittable?(status)
    end

    test "a proof the author never captured is missing and blocks" do
      status = Proofs.status(:none, observed([]), %{})

      assert status.review_password_sign_hash == :missing
      refute Proofs.submittable?(status)
    end

    test "a promoted row the author did not sign is a mismatch and blocks" do
      status = Proofs.status(:none, observed(password: "rvps_other"), @local)

      assert status.review_password_sign_hash == :mismatch
      refute Proofs.submittable?(status)
    end

    test "forbidden slots stay out of the way" do
      status = Proofs.status(:none, observed(password: @password), @local)

      assert status.post_right_sign_hash == :not_applicable
      assert status.revoke_right_sign_hash == :not_applicable
      assert Proofs.submittable?(status)
    end

    test "a mismatched right blocks in pre mode" do
      observed = observed(post: "rvprs_other", revoke: @revoke)
      status = Proofs.status(:pre, observed, @local)

      assert status.post_right_sign_hash == :mismatch
      refute Proofs.submittable?(status)
    end
  end

  describe "password_published?/1" do
    test "false while the origin has not published" do
      status = Proofs.status(:pre, observed(post: @post, revoke: @revoke), @local)

      refute Proofs.password_published?(status)
    end

    test "true once the observed promotion row matches what the author signed" do
      observed = observed(password: @password, post: @post, revoke: @revoke)
      status = Proofs.status(:pre, observed, @local)

      assert Proofs.password_published?(status)
    end

    test "false when a different promotion row shows up" do
      observed = observed(password: "rvps_other", post: @post, revoke: @revoke)
      status = Proofs.status(:pre, observed, @local)

      refute Proofs.password_published?(status)
    end
  end

  defp observed(opts) do
    %{
      review_password_sign_hash: opts[:password],
      post_right_sign_hash: opts[:post],
      revoke_right_sign_hash: opts[:revoke]
    }
  end
end
