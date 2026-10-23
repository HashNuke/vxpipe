defmodule Vxpipe.Persistence.OAuth.RateLimitTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Persistence.OAuth.RateLimit

  @now 1_800_000_000

  test "per-address denials remain durable and operations have separate budgets" do
    options = [now: @now, per_address: 2, global: 10]
    assert :ok = RateLimit.check(:token, "192.0.2.1", options)
    assert :ok = RateLimit.check(:token, "192.0.2.1", options)
    assert {:error, :rate_limited} = RateLimit.check(:token, "192.0.2.1", options)
    assert {:error, :rate_limited} = RateLimit.check(:token, "192.0.2.1", options)
    assert :ok = RateLimit.check(:token, "192.0.2.2", options)
    assert :ok = RateLimit.check(:authorize, "192.0.2.1", options)
  end

  test "the global budget bounds accepted callers and retained address rows" do
    options = [now: @now, per_address: 2, global: 3]
    for n <- 1..3, do: assert(:ok == RateLimit.check(:register, "192.0.2.#{n}", options))

    for n <- 4..12 do
      assert {:error, :rate_limited} = RateLimit.check(:register, "192.0.2.#{n}", options)
    end

    assert %{rows: [[4]]} = Repo.query!("SELECT count(*) FROM oauth_rate_limits")

    assert %{rows: [[4]]} =
             Repo.query!("SELECT attempts FROM oauth_rate_limits WHERE bucket = 'global'")
  end

  test "window rollover restores capacity and removes old counters" do
    options = [now: @now, per_address: 1, global: 10]
    assert :ok = RateLimit.check(:revoke, "2001:db8::1", options)
    assert {:error, :rate_limited} = RateLimit.check(:revoke, "2001:db8::1", options)
    assert :ok = RateLimit.check(:revoke, "2001:db8::1", Keyword.put(options, :now, @now + 60))
    assert :ok = RateLimit.check(:revoke, "2001:db8::1", Keyword.put(options, :now, @now + 180))
    assert %{rows: [[oldest]]} = Repo.query!("SELECT min(window_start) FROM oauth_rate_limits")
    assert oldest == @now + 60
  end

  test "canonical literal addresses are hashed at rest and malformed identity fails closed" do
    assert :ok = RateLimit.check(:authorize, "2001:db8::1", now: @now)

    assert %{rows: [[digest]]} =
             Repo.query!("SELECT identity_digest FROM oauth_rate_limits WHERE bucket = 'address'")

    assert digest == :crypto.hash(:sha256, "2001:db8::1")

    for address <- ["2001:0db8:0:0:0:0:0:1", "192.000.2.1", "client.example", "", nil, <<255>>] do
      assert {:error, :unavailable} = RateLimit.check(:token, address, now: @now)
    end

    assert {:error, :unavailable} = RateLimit.check(:unknown, "192.0.2.1", now: @now)
  end

  test "production operation limits are enforced without caller configuration" do
    for {operation, limit} <- [register: 10, authorize: 60, token: 120, revoke: 60] do
      for _ <- 1..limit, do: assert(:ok == RateLimit.check(operation, "192.0.2.10", now: @now))
      assert {:error, :rate_limited} = RateLimit.check(operation, "192.0.2.10", now: @now)
    end
  end
end
