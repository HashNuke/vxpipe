defmodule Vxpipe.Persistence.MCP.RepositoryBoundaryTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Persistence.MCP.{OAuthAttemptStore, RepositoryBoundary}
  alias Vxpipe.Persistence.Repo

  test "OAuth scope lookup maps a stopped repository with pending registry cleanup to storage unavailable" do
    repository =
      start_supervised!({Repo, name: __MODULE__.Repo, pool_size: 1})

    monitor = Process.monitor(repository)
    previous = Repo.get_dynamic_repo()
    registry = Process.whereis(Ecto.Repo.Registry)
    :ok = :sys.suspend(registry)

    try do
      stop_supervised!(Repo)
      assert_receive {:DOWN, ^monitor, :process, ^repository, :shutdown}
      Repo.put_dynamic_repo(repository)

      # A legitimate scheduler interleaving: the repo is down while Ecto's
      # registry has not yet consumed its monitor message.
      %{cache: cache} = Ecto.Repo.Registry.lookup(repository)
      assert :ets.info(cache) == :undefined

      assert {:error, :mcp_oauth_storage_unavailable} =
               OAuthAttemptStore.locate(
                 [repo: Repo],
                 String.duplicate("s", 43),
                 %{user_id: "user", session_id: "session"}
               )
    after
      Repo.put_dynamic_repo(previous)
      :ok = :sys.resume(registry)
    end
  end

  test "an unrelated ArgumentError stays a programmer failure" do
    assert_raise ArgumentError, "programmer mistake", fn ->
      RepositoryBoundary.call(fn -> raise ArgumentError, "programmer mistake" end, :unavailable)
    end
  end

  test "an unrelated deleted ETS table remains a programmer failure" do
    cache = :ets.new(:unrelated_cache, [:set])
    :ets.delete(cache)

    assert_raise ArgumentError, fn ->
      RepositoryBoundary.call(fn -> :ets.lookup(cache, :key) end, :unavailable)
    end
  end
end
