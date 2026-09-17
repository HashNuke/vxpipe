defmodule Vxpipe.Calls.Test.OperatorLoginChallengeRepository do
  @behaviour Vxpipe.Calls.OperatorLoginChallengeRepository

  @impl true
  def insert(owner, challenge) do
    send(owner, {:insert_operator_login_challenge, challenge})
    {:ok, challenge}
  end

  @impl true
  def consume(owner, token_digest, code_verifier) do
    send(owner, {:consume_operator_login_challenge, token_digest, code_verifier})

    :ok
  end
end
