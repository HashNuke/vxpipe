defmodule Vxpipe.Identity.SessionsPolicyTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.{RateLimit, Sessions, Tokens}

  defmodule ValidSessions do
    @behaviour Vxpipe.Identity.Ports.Sessions
    @impl true
    def create(attrs), do: {:ok, attrs}
    @impl true
    def fetch_valid(_digest, _now), do: {:ok, %{public_id: "sess-1", user_public_id: "user-1"}}
    @impl true
    def revoke_one(_digest, _now), do: :ok
    @impl true
    def revoke_for_user(_, _), do: {:ok, 1}
    @impl true
    def revoke_for_role(_, _), do: {:ok, 1}
  end

  defmodule FailingRevokeSessions do
    @behaviour Vxpipe.Identity.Ports.Sessions
    @impl true
    def create(attrs), do: {:ok, attrs}
    @impl true
    def fetch_valid(_digest, _now), do: {:ok, %{public_id: "sess-1", user_public_id: "user-1"}}
    @impl true
    def revoke_one(_digest, _now), do: {:error, :unavailable}
    @impl true
    def revoke_for_user(_, _), do: {:error, :unavailable}
    @impl true
    def revoke_for_role(_, _), do: {:error, :unavailable}
  end

  defmodule UnavailableSessions do
    @behaviour Vxpipe.Identity.Ports.Sessions
    @impl true
    def create(_), do: {:error, :unavailable}
    @impl true
    def fetch_valid(_digest, _now), do: {:error, :unavailable}
    @impl true
    def revoke_one(_digest, _now), do: {:error, :unavailable}
    @impl true
    def revoke_for_user(_, _), do: {:error, :unavailable}
    @impl true
    def revoke_for_role(_, _), do: {:error, :unavailable}
  end

  defmodule MissingSessions do
    @behaviour Vxpipe.Identity.Ports.Sessions
    @impl true
    def create(attrs), do: {:ok, attrs}
    @impl true
    def fetch_valid(_digest, _now), do: {:error, :not_found}
    @impl true
    def revoke_one(_digest, _now), do: {:ok, 0}
    @impl true
    def revoke_for_user(_, _), do: {:ok, 0}
    @impl true
    def revoke_for_role(_, _), do: {:ok, 0}
  end

  test "session TTL is 12 hours" do
    assert Tokens.session_ttl_seconds() == 12 * 3600
  end

  test "only digests are stored; token itself is never the lookup key" do
    {:ok, %{token: token, digest: digest}} = Tokens.generate()
    refute token == digest
    assert digest == Tokens.digest(token)
    assert String.length(token) >= 32
  end

  test "rate limit trips after bounded attempts and recovers after window" do
    now = ~U[2026-10-13 00:00:00Z]
    old = DateTime.add(now, -901, :second)
    account = for _ <- 1..10, do: now
    assert {:error, :rate_limited} = RateLimit.allowed?(account, [], now)
    assert :ok = RateLimit.allowed?(for(_ <- 1..10, do: old), [], now)
    assert :ok = RateLimit.allowed?(for(_ <- 1..9, do: now), [], now)
  end

  test "logout propagates revoke failure instead of claiming success" do
    deps = %{sessions: FailingRevokeSessions, audit: Vxpipe.Identity.Accounts.NoopAudit}
    assert {:error, :unavailable} = Sessions.logout(deps, "any-token-value-1234567890abcdef")
  end

  test "logout fails closed when session lookup is unavailable" do
    deps = %{sessions: UnavailableSessions, audit: Vxpipe.Identity.Accounts.NoopAudit}
    assert {:error, :unavailable} = Sessions.logout(deps, "any-token-value-1234567890abcdef")
  end

  test "logout stays idempotent for missing sessions" do
    deps = %{sessions: MissingSessions, audit: Vxpipe.Identity.Accounts.NoopAudit}
    assert :ok = Sessions.logout(deps, "any-token-value-1234567890abcdef")
  end
end
