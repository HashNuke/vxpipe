defmodule Vxpipe.Identity.BootstrapAuditTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.Bootstrap

  defmodule PendingFirstRun do
    @behaviour Vxpipe.Identity.Ports.Installations
    @impl true
    def fetch, do: {:ok, %{mode: :first_run, setup_completed_at: nil}}
    @impl true
    def complete_first_run(attrs),
      do:
        {:ok,
         %{
           user: Map.put(attrs, :public_id, attrs.user_public_id),
           session: %{public_id: attrs.session_public_id}
         }}

    @impl true
    def consume_setup_proof(_proof, _attrs), do: {:error, :invalid_proof}
    @impl true
    def issue_setup_proof(_ttl), do: {:ok, %{proof: "p"}}
    @impl true
    def issue_recovery_proof(_ttl), do: {:error, :not_complete}
    @impl true
    def consume_recovery_proof(_proof, _attrs), do: {:error, :not_complete}
  end

  defmodule FailingAudit do
    @behaviour Vxpipe.Identity.Ports.Audit
    @impl true
    def append(_), do: {:error, :unavailable}
  end

  defp deps(audit) do
    %{
      installations: PendingFirstRun,
      hasher: Vxpipe.Identity.FakeHasher,
      tokens: Vxpipe.Identity.Tokens,
      uuid: Vxpipe.Identity.FakeUuid,
      audit: audit
    }
  end

  test "setup does not report false failure when outer audit sink fails but store committed" do
    # Store committed (fake returns ok); durable audit lives in the atomic store
    # operation, so a failing outer audit sink must not turn success into error.
    assert {:ok, %{token: _}} =
             Bootstrap.complete_first_run(
               deps(FailingAudit),
               "root@example.com",
               "correct horse 15!",
               "correct horse 15!"
             )
  end
end
