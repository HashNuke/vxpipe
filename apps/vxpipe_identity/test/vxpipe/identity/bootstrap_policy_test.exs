defmodule Vxpipe.Identity.BootstrapPolicyTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.Bootstrap

  defmodule PendingFirstRun do
    @behaviour Vxpipe.Identity.Ports.Installations
    @impl true
    def fetch, do: {:ok, %{mode: :first_run, setup_completed_at: nil}}
    @impl true
    def complete_first_run(attrs), do: {:ok, %{user: Map.put(attrs, :public_id, attrs.user_public_id), session: %{public_id: attrs.session_public_id}}}
    @impl true
    def consume_setup_proof(_proof, _attrs), do: {:error, :invalid_proof}
    @impl true
    def issue_setup_proof(_ttl), do: {:ok, %{proof: "p"}}
    @impl true
    def issue_recovery_proof(_ttl), do: {:error, :not_complete}
    @impl true
    def consume_recovery_proof(_proof, _attrs), do: {:error, :not_complete}
  end

  defmodule PendingOperator do
    @behaviour Vxpipe.Identity.Ports.Installations
    @impl true
    def fetch, do: {:ok, %{mode: :operator_required, setup_completed_at: nil}}
    @impl true
    def complete_first_run(_attrs), do: {:error, :proof_required}
    @impl true
    def consume_setup_proof("good-proof", attrs), do: {:ok, %{user: Map.put(attrs, :public_id, attrs.user_public_id), session: %{public_id: attrs.session_public_id}}}
    @impl true
    def consume_setup_proof(_proof, _attrs), do: {:error, :invalid_proof}
    @impl true
    def issue_setup_proof(_ttl), do: {:ok, %{proof: "good-proof"}}
    @impl true
    def issue_recovery_proof(_ttl), do: {:error, :not_complete}
    @impl true
    def consume_recovery_proof(_proof, _attrs), do: {:error, :not_complete}
  end

  defp deps(installations),
    do: %{installations: installations, hasher: Vxpipe.Identity.FakeHasher, tokens: Vxpipe.Identity.Tokens, uuid: Vxpipe.Identity.FakeUuid, audit: Vxpipe.Identity.Accounts.NoopAudit}

  test "fresh install may complete first run without proof" do
    assert {:ok, :pending_first_run} = Bootstrap.status(deps(PendingFirstRun))
    assert {:ok, %{token: token}} = Bootstrap.complete_first_run(deps(PendingFirstRun), "root@example.com", "correct horse 15!", "correct horse 15!")
    assert is_binary(token)
  end

  test "upgraded install rejects anonymous claim and requires trusted proof" do
    assert {:ok, :pending_operator_proof} = Bootstrap.status(deps(PendingOperator))
    assert {:error, :proof_required} = Bootstrap.complete_first_run(deps(PendingOperator), "root@example.com", "correct horse 15!", "correct horse 15!")
    assert {:error, :invalid_proof} = Bootstrap.complete_with_proof(deps(PendingOperator), "bad", "root@example.com", "correct horse 15!", "correct horse 15!")

    assert {:ok, %{token: _}} =
             Bootstrap.complete_with_proof(deps(PendingOperator), "good-proof", "root@example.com", "correct horse 15!", "correct horse 15!")
  end

  defmodule ThrottledAttempts do
    @behaviour Vxpipe.Identity.Ports.Attempts
    @impl true
    def record(_, _, _), do: :ok
    @impl true
    def recent(_, _, now, _), do: {:ok, %{account: for(_ <- 1..10, do: now), address: []}}
  end

  defmodule UnavailableAttempts do
    @behaviour Vxpipe.Identity.Ports.Attempts
    @impl true
    def record(_, _, _), do: {:error, :unavailable}
    @impl true
    def recent(_, _, _, _), do: {:error, :unavailable}
  end

  test "bootstrap submissions are throttled and fail closed on store outage" do
    throttled = Map.put(deps(PendingFirstRun), :attempts, ThrottledAttempts)

    assert {:error, :rate_limited} =
             Bootstrap.complete_first_run(throttled, "root@example.com", "correct horse 15!", "correct horse 15!")

    assert {:error, :rate_limited} =
             Bootstrap.complete_with_proof(
               Map.put(deps(PendingOperator), :attempts, ThrottledAttempts),
               "good-proof",
               "root@example.com",
               "correct horse 15!",
               "correct horse 15!"
             )

    unavailable = Map.put(deps(PendingFirstRun), :attempts, UnavailableAttempts)

    assert {:error, :unavailable} =
             Bootstrap.complete_first_run(unavailable, "root@example.com", "correct horse 15!", "correct horse 15!")
  end

  defmodule CompleteInstallation do
    @behaviour Vxpipe.Identity.Ports.Installations
    @impl true
    def fetch, do: {:ok, %{mode: :first_run, setup_completed_at: ~U[2026-10-13 01:00:00Z]}}
    @impl true
    def complete_first_run(_), do: {:error, :already_completed}
    @impl true
    def consume_setup_proof(_, _), do: {:error, :already_completed}
    @impl true
    def issue_setup_proof(_), do: {:ok, %{proof: "p"}}
    @impl true
    def issue_recovery_proof(_), do: {:ok, %{proof: "recovery-proof"}}
    @impl true
    def consume_recovery_proof("good-recovery", attrs),
      do: {:ok, %{user: Map.put(attrs, :public_id, "user-1"), session: %{public_id: attrs.session_public_id}}}

    def consume_recovery_proof(_, _), do: {:error, :invalid_proof}
  end

  test "recovery requires a valid one-time proof and is throttled" do
    complete = Map.put(deps(CompleteInstallation), :attempts, ThrottledAttempts)

    assert {:error, :rate_limited} =
             Bootstrap.recover_with_proof(
               complete,
               "good-recovery",
               "root@example.com",
               "new recovery password 15!",
               "new recovery password 15!"
             )

    assert {:error, :invalid_proof} =
             Bootstrap.recover_with_proof(
               deps(CompleteInstallation),
               "bad",
               "root@example.com",
               "new recovery password 15!",
               "new recovery password 15!"
             )

    assert {:ok, %{token: _}} =
             Bootstrap.recover_with_proof(
               deps(CompleteInstallation),
               "good-recovery",
               "root@example.com",
               "new recovery password 15!",
               "new recovery password 15!"
             )

    assert {:ok, %{proof: "recovery-proof"}} =
             Bootstrap.issue_recovery_proof(deps(CompleteInstallation))
  end
end
