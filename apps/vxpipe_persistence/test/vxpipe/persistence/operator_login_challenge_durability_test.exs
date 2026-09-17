defmodule Vxpipe.Persistence.OperatorLoginChallengeDurabilityTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls.OperatorLoginChallenges
  alias Vxpipe.Persistence.{OperatorLoginChallengeStore, Repo}
  alias Vxpipe.Persistence.Schema.OperatorLoginChallenge

  @secret :binary.copy(<<91>>, 32)

  setup do
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      ensure_repo_started()
      Repo.delete_all(from(challenge in OperatorLoginChallenge))
      Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

  test "two concurrent correct submissions consume exactly once" do
    assert {:ok, issued} = OperatorLoginChallenges.issue(@secret, options())
    parent = self()

    tasks =
      for _submission <- 1..2 do
        Task.async(fn ->
          send(parent, {:submission_ready, self()})

          receive do
            :submit ->
              OperatorLoginChallenges.consume(issued.token, issued.code, @secret, options())
          end
        end)
      end

    task_pids =
      for _submission <- 1..2 do
        assert_receive {:submission_ready, task_pid}
        task_pid
      end

    Enum.each(task_pids, &send(&1, :submit))

    assert tasks |> Enum.map(&Task.await(&1, 5_000)) |> Enum.sort() ==
             [:ok, {:error, :invalid_operator_login_challenge}]
  end

  test "failed and consumed state remain authoritative after a Repo restart" do
    assert {:ok, failed_once} = OperatorLoginChallenges.issue(@secret, options())
    assert {:ok, consumed} = OperatorLoginChallenges.issue(@secret, options())

    for attempt <- 1..4 do
      assert {:error, :invalid_operator_login_challenge} =
               OperatorLoginChallenges.consume(
                 failed_once.token,
                 "wrong-#{attempt}",
                 @secret,
                 options()
               )
    end

    assert :ok =
             OperatorLoginChallenges.consume(consumed.token, consumed.code, @secret, options())

    restart_repo!()

    assert {:error, :invalid_operator_login_challenge} =
             OperatorLoginChallenges.consume(failed_once.token, "fifth", @secret, options())

    restart_repo!()

    assert {:error, :invalid_operator_login_challenge} =
             OperatorLoginChallenges.consume(
               failed_once.token,
               failed_once.code,
               @secret,
               options()
             )

    assert {:error, :invalid_operator_login_challenge} =
             OperatorLoginChallenges.consume(consumed.token, consumed.code, @secret, options())
  end

  test "expired state remains invalid after a Repo restart" do
    issued_at = DateTime.add(DateTime.utc_now(), -601, :second)
    assert {:ok, issued} = OperatorLoginChallenges.issue(@secret, options(now: issued_at))

    restart_repo!()

    assert {:error, :invalid_operator_login_challenge} =
             OperatorLoginChallenges.consume(issued.token, issued.code, @secret, options())
  end

  test "an unavailable repository fails safely" do
    assert :ok = Supervisor.terminate_child(Vxpipe.Persistence.TestSupervisor, Repo)

    assert {:error, :repository_unavailable} =
             OperatorLoginChallenges.issue(@secret, options())

    assert {:ok, _repo} = Supervisor.restart_child(Vxpipe.Persistence.TestSupervisor, Repo)
    Sandbox.mode(Repo, :auto)
  end

  defp options(overrides \\ []) do
    Keyword.merge(
      [
        operator_login_challenge_repository:
          {OperatorLoginChallengeStore, [repo: Repo, now: &DateTime.utc_now/0]}
      ],
      overrides
    )
  end

  defp restart_repo! do
    assert :ok = Supervisor.terminate_child(Vxpipe.Persistence.TestSupervisor, Repo)
    assert {:ok, _repo} = Supervisor.restart_child(Vxpipe.Persistence.TestSupervisor, Repo)
    Sandbox.mode(Repo, :auto)
  end

  defp ensure_repo_started do
    case Process.whereis(Repo) do
      nil ->
        assert {:ok, _repo} = Supervisor.restart_child(Vxpipe.Persistence.TestSupervisor, Repo)
        Sandbox.mode(Repo, :auto)

      _pid ->
        :ok
    end
  end
end
