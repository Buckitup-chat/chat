defmodule ChatWeb.ChallengeController do
  use ChatWeb, :controller

  alias Chat.Challenge

  def create(conn, _params) do
    {challenge_id, challenge} = Challenge.store()

    json(conn, %{
      challenge_id: challenge_id,
      challenge: challenge,
      expires_in: Challenge.expiration_seconds()
    })
  end
end
