defmodule Vxpipe.Persistence.RestartTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.Tenant

  test "persisted API-key authentication survives a Repo restart" do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    tenant_key = Vxpipe.Calls.PublicId.tenant_key()
    options = [credential_repository: {CredentialStore, Repo}]

    on_exit(fn ->
      Repo.delete_all(from tenant in Tenant, where: tenant.key == ^tenant_key)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    assert {:ok, tenant, issued} =
             Administration.bootstrap_tenant("Restart check", [:calls], options)

    assert :ok =
             Supervisor.terminate_child(Vxpipe.Persistence.TestSupervisor, Repo)

    assert {:ok, _repo} =
             Supervisor.restart_child(Vxpipe.Persistence.TestSupervisor, Repo)

    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    assert {:ok, principal} =
             Administration.authenticate(tenant.key, issued.secret, :calls, options)

    assert principal.api_key_id == issued.id
    assert {:error, :invalid_api_key} =
             Administration.authenticate(tenant.key, "not-the-key", :calls, options)
  end
end
