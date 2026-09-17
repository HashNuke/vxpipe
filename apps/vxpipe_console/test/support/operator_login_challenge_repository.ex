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
  def consume({owner, :raise}, token_digest, code_verifier) do
    send(owner, {:operator_login_challenge_consumed, token_digest, code_verifier})
    raise "forced operator login repository error"
  end

  def consume({owner, result}, token_digest, code_verifier) do
    send(owner, {:operator_login_challenge_consumed, token_digest, code_verifier})
    result
  end

  def consume(owner, token_digest, code_verifier) do
    send(owner, {:operator_login_challenge_consumed, token_digest, code_verifier})
    :ok
  end

  def handle_telemetry([:phoenix, :router_dispatch, phase], _measurements, metadata, owner) do
    send(owner, {:operator_login_router_telemetry, phase, metadata})
  end

  def handle_telemetry([:phoenix, :error_rendered], _measurements, metadata, owner) do
    send(owner, {:operator_login_router_telemetry, :error_rendered, metadata})
  end
end
