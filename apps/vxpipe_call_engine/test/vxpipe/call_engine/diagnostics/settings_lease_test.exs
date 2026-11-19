defmodule Vxpipe.CallEngine.Diagnostics.SettingsLeaseTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.SettingsLease

  test "unknown authority cannot enable capture; a lease expires exactly three seconds after read start" do
    lease = SettingsLease.new("boot")
    assert {:unavailable, :unknown_settings} = SettingsLease.status(lease, -10_000, "boot")
    assert {:ok, lease} = SettingsLease.accept(lease, snapshot(true, 1), -10_000, -9_900, "boot")
    assert {:enabled, 1} = SettingsLease.status(lease, -7_001, "boot")
    assert {:unavailable, :expired_settings} = SettingsLease.status(lease, -7_000, "boot")
  end

  test "a slow database response cannot mint a fresh lease from old enabled evidence" do
    lease = SettingsLease.new("boot")

    assert {:error, :expired_settings, expired} =
             SettingsLease.accept(lease, snapshot(true, 1), 0, 3_000, "boot")

    assert {:unavailable, :expired_settings} = SettingsLease.status(expired, 3_000, "boot")
  end

  test "newer disable wins and delayed older replies cannot restore enabled authority" do
    lease = SettingsLease.new("boot")
    assert {:ok, lease} = SettingsLease.accept(lease, snapshot(true, 1), 0, 10, "boot")
    assert {:ok, disabled} = SettingsLease.accept(lease, snapshot(false, 2), 20, 30, "boot")

    assert {:error, :stale_response, ^disabled} =
             SettingsLease.accept(disabled, snapshot(true, 1), 0, 40, "boot")

    assert {:disabled, 2} = SettingsLease.status(disabled, 40, "boot")
  end

  test "only a later authoritative read can refresh an unchanged revision" do
    lease = SettingsLease.new("boot")
    assert {:ok, lease} = SettingsLease.accept(lease, snapshot(true, 1), 0, 10, "boot")

    assert {:error, :stale_response, ^lease} =
             SettingsLease.accept(lease, snapshot(true, 1), 0, 20, "boot")

    assert {:ok, refreshed} = SettingsLease.accept(lease, snapshot(true, 1), 2_000, 2_010, "boot")
    assert {:enabled, 1} = SettingsLease.status(refreshed, 4_999, "boot")
    assert {:unavailable, :expired_settings} = SettingsLease.status(refreshed, 5_000, "boot")
  end

  test "conflicting contents for a revision invalidate authority until a higher revision" do
    lease = SettingsLease.new("boot")
    assert {:ok, lease} = SettingsLease.accept(lease, snapshot(true, 1), 0, 10, "boot")

    assert {:error, :conflicting_revision, invalid} =
             SettingsLease.accept(lease, snapshot(false, 1), 20, 30, "boot")

    assert {:unavailable, :conflicting_revision} = SettingsLease.status(invalid, 30, "boot")

    assert {:error, :conflicting_revision, _} =
             SettingsLease.accept(invalid, snapshot(true, 1), 40, 50, "boot")

    assert {:ok, recovered} = SettingsLease.accept(invalid, snapshot(false, 2), 60, 70, "boot")
    assert {:disabled, 2} = SettingsLease.status(recovered, 70, "boot")
  end

  test "foreign clocks, backward time and malformed authority cannot enable collection" do
    lease = SettingsLease.new("boot")
    assert {:ok, lease} = SettingsLease.accept(lease, snapshot(true, 1), 0, 10, "boot")
    assert {:unavailable, :clock_mismatch} = SettingsLease.status(lease, 20, "other")
    assert {:unavailable, :clock_uncertain} = SettingsLease.status(lease, 9, "boot")

    for {value, started, now, clock} <- [
          {snapshot(true, 2), 20, 19, "boot"},
          {snapshot(true, 2), 20, 30, "other"},
          {%{enabled: "true", revision: 2}, 20, 30, "boot"},
          {snapshot(true, -1), 20, 30, "boot"},
          {%{enabled: true, revision: 2, extra: :authority}, 20, 30, "boot"}
        ] do
      assert {:error, _, invalid} = SettingsLease.accept(lease, value, started, now, clock)
      assert {:unavailable, _} = SettingsLease.status(invalid, 30, "boot")
    end
  end

  test "a later malformed response cannot erase a same-revision conflict" do
    lease = SettingsLease.new("boot")
    assert {:ok, lease} = SettingsLease.accept(lease, snapshot(true, 1), 0, 10, "boot")

    assert {:error, :conflicting_revision, invalid} =
             SettingsLease.accept(lease, snapshot(false, 1), 20, 30, "boot")

    assert {:error, :invalid_settings, invalid} =
             SettingsLease.accept(invalid, %{enabled: "true", revision: 2}, 40, 50, "boot")

    assert {:error, :conflicting_revision, invalid} =
             SettingsLease.accept(invalid, snapshot(true, 1), 60, 70, "boot")

    assert {:unavailable, :conflicting_revision} = SettingsLease.status(invalid, 70, "boot")
  end

  defp snapshot(enabled, revision), do: %{enabled: enabled, revision: revision}
end
