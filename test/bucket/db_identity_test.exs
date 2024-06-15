defmodule BucketTest.DbIdentityTest do
  use ExUnit.Case, async: true

  alias Bucket.Identity.DbIdentity

  test "keeps private key in db" do
    pub_key = DbIdentity.get_pub_key()

    assert DbIdentity.ready?()

    assert pub_key == DbIdentity.get_pub_key()
  end
end
