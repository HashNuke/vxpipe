defmodule Vxpipe.Persistence.Integration.OAuthRateLimitConcurrencyTest do
  use ExUnit.Case, async: false
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Persistence.OAuth.RateLimit
  alias Vxpipe.Persistence.Repo
  @moduletag :integration
  @now 1_900_000_020

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    clear_counters()

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      clear_counters()
      Sandbox.checkin(Repo)
    end)

    :ok
  end

  test "distinct connections enforce the per-address budget and commit denials" do
    results = race(List.duplicate("192.0.2.12", 4), per_address: 2, global: 6)
    assert Enum.count(results, &(&1 == :ok)) == 2
    assert Enum.count(results, &(&1 == {:error, :rate_limited})) == 2

    assert %{rows: [[2]]} =
             Repo.query!(
               "SELECT count(*) FROM oauth_rate_limits WHERE operation = 'token' AND window_start = $1",
               [@now]
             )

    assert {:error, :rate_limited} =
             RateLimit.check(:token, "192.0.2.12", now: @now, per_address: 2, global: 6)
  end

  test "distinct connections cannot exceed the global budget or create denied address rows" do
    results = race(Enum.map(1..4, &"192.0.2.#{&1}"), per_address: 2, global: 3)
    assert Enum.count(results, &(&1 == :ok)) == 3
    assert Enum.count(results, &(&1 == {:error, :rate_limited})) == 1

    assert %{rows: [[4]]} =
             Repo.query!(
               "SELECT count(*) FROM oauth_rate_limits WHERE operation = 'token' AND window_start = $1",
               [@now]
             )

    assert {:error, :rate_limited} =
             RateLimit.check(:token, "192.0.2.99", now: @now, per_address: 2, global: 3)

    assert %{rows: [[4]]} =
             Repo.query!(
               "SELECT count(*) FROM oauth_rate_limits WHERE operation = 'token' AND window_start = $1",
               [@now]
             )
  end

  defp race(addresses, options) do
    observer = self()
    options = Keyword.put(options, :now, @now)

    workers =
      addresses
      |> Enum.with_index()
      |> Enum.map(fn {address, index} ->
        pid =
          start_supervised!(
            {Task,
             fn ->
               :ok = Sandbox.checkout(Repo, sandbox: false)
               %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
               send(observer, {:ready, self(), connection})

               receive do
                 :admit ->
                   send(observer, {:result, self(), RateLimit.check(:token, address, options)})
               after
                 5_000 -> send(observer, {:result, self(), {:error, :test_timeout}})
               end

               Sandbox.checkin(Repo)
             end},
            id: {:rate_racer, index}
          )

        {pid, Process.monitor(pid)}
      end)

    connections =
      Enum.map(workers, fn {pid, _} ->
        assert_receive {:ready, ^pid, connection}, 5_000
        connection
      end)

    assert length(Enum.uniq(connections)) == length(workers)
    Enum.each(workers, fn {pid, _} -> send(pid, :admit) end)

    Enum.map(workers, fn {pid, monitor} ->
      assert_receive {:result, ^pid, result}, 5_000
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
      result
    end)
  end

  defp clear_counters,
    do:
      Repo.query!(
        "DELETE FROM oauth_rate_limits WHERE operation = 'token' AND window_start = $1",
        [@now]
      )
end
