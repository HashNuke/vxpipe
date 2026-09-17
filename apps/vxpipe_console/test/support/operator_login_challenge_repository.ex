defmodule Vxpipe.Console.Test.OperatorLoginChallengeRepository do
  @behaviour Vxpipe.Calls.OperatorLoginChallengeRepository

  @impl true
  def insert({owner, :unavailable}, challenge) do
    send(owner, {:operator_login_challenge_inserted, challenge})
    {:error, :repository_unavailable}
  end

  def insert(owner, challenge) do
    send(owner, {:operator_login_challenge_inserted, challenge})
    {:ok, challenge}
  end

  @impl true
  def consume(_owner, _token_digest, _code_verifier), do: :ok
end
