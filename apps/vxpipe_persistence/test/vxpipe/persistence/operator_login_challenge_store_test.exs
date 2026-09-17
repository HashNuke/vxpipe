defmodule Vxpipe.Persistence.OperatorLoginChallengeStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Calls.OperatorLoginChallenges
  alias Vxpipe.Persistence.{OperatorLoginChallengeStore, Repo}
  alias Vxpipe.Persistence.Schema.OperatorLoginChallenge

  @now ~U[2026-09-17 08:00:00.000000Z]
  @secret :binary.copy(<<77>>, 32)

  test "persists only digests and consumes the correct challenge once" do
    assert {:ok, issued} = OperatorLoginChallenges.issue(@secret, options())

    stored = Repo.one!(from(challenge in OperatorLoginChallenge))
    assert byte_size(stored.token_digest) == 32
    assert byte_size(stored.code_verifier) == 32
    assert stored.failed_attempts == 0
    assert stored.issued_at == @now
    assert stored.expires_at == DateTime.add(@now, 600, :second)
    assert stored.consumed_at == nil
    refute Map.has_key?(Map.from_struct(stored), :token)
    refute Map.has_key?(Map.from_struct(stored), :code)

    assert :ok = OperatorLoginChallenges.consume(issued.token, issued.code, @secret, options())

    assert {:error, :invalid_operator_login_challenge} =
             OperatorLoginChallenges.consume(issued.token, issued.code, @secret, options())

    assert %DateTime{} = Repo.reload!(stored).consumed_at
  end

  test "five incorrect submissions exhaust the challenge and persist their attempts" do
    assert {:ok, issued} = OperatorLoginChallenges.issue(@secret, options())

    for failed_attempt <- 1..5 do
      assert {:error, :invalid_operator_login_challenge} =
               OperatorLoginChallenges.consume(
                 issued.token,
                 Integer.to_string(failed_attempt),
                 @secret,
                 options()
               )

      assert Repo.one!(from(challenge in OperatorLoginChallenge)).failed_attempts ==
               failed_attempt
    end

    assert {:error, :invalid_operator_login_challenge} =
             OperatorLoginChallenges.consume(issued.token, issued.code, @secret, options())
  end

  test "an expired challenge stays invalid" do
    assert {:ok, issued} = OperatorLoginChallenges.issue(@secret, options())
    expired_at = DateTime.add(@now, 600, :second)

    assert {:error, :invalid_operator_login_challenge} =
             OperatorLoginChallenges.consume(
               issued.token,
               issued.code,
               @secret,
               options(now: expired_at)
             )

    assert Repo.one!(from(challenge in OperatorLoginChallenge)).consumed_at == nil
  end

  test "a missing challenge table fails safely" do
    Repo.query!("ALTER TABLE operator_login_challenges RENAME TO unavailable_login_challenges")

    assert {:error, :repository_unavailable} =
             OperatorLoginChallenges.issue(@secret, options())
  end

  defp options(overrides \\ []) do
    current_time = Keyword.get(overrides, :now, @now)

    Keyword.merge(
      [
        operator_login_challenge_repository:
          {OperatorLoginChallengeStore, [repo: Repo, now: fn -> current_time end]},
        now: current_time
      ],
      overrides
    )
  end
end
