defmodule Vxpipe.Persistence.DemoTenantStore do
  @moduledoc "Transactional storage for the installation's demo-tenant identity."

  @behaviour Vxpipe.Calls.DemoTenantRepository

  import Ecto.Query

  alias Vxpipe.Calls.Tenant, as: DomainTenant
  alias Vxpipe.Persistence.Schema.{InstallationSetup, Tenant}

  @setup_key "default"

  @impl true
  def ensure(repo, %DomainTenant{} = candidate) do
    repository_result(fn ->
      case fetch(repo) do
        {:ok, tenant} ->
          {:ok, tenant}

        {:error, :not_found} ->
          candidate
          |> insert_binding(repo)
          |> resume_after_conflict(repo)
      end
    end)
  end

  defp insert_binding(candidate, repo) do
    repo.transaction(fn ->
      with {:ok, tenant} <- insert_tenant(repo, candidate),
           {:ok, _setup} <- insert_setup(repo, tenant.id) do
        to_domain(tenant)
      else
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  defp resume_after_conflict({:error, :setup_conflict}, repo), do: fetch(repo)
  defp resume_after_conflict(result, _repo), do: result

  defp fetch(repo) do
    query =
      from(setup in InstallationSetup,
        join: tenant in assoc(setup, :demo_tenant),
        where: setup.key == ^@setup_key,
        select: tenant
      )

    case repo.one(query) do
      nil -> {:error, :not_found}
      tenant -> {:ok, to_domain(tenant)}
    end
  end

  defp insert_tenant(repo, candidate) do
    %Tenant{}
    |> Tenant.changeset(%{key: candidate.key, name: candidate.name})
    |> repo.insert()
    |> case do
      {:ok, tenant} -> {:ok, tenant}
      {:error, changeset} -> {:error, tenant_error(changeset)}
    end
  end

  defp insert_setup(repo, tenant_id) do
    %InstallationSetup{}
    |> InstallationSetup.changeset(%{key: @setup_key, demo_tenant_id: tenant_id})
    |> repo.insert()
    |> case do
      {:ok, setup} -> {:ok, setup}
      {:error, _changeset} -> {:error, :setup_conflict}
    end
  end

  defp tenant_error(changeset) do
    if Keyword.has_key?(changeset.errors, :key),
      do: :tenant_key_conflict,
      else: :tenant_insert_failed
  end

  defp to_domain(tenant) do
    %DomainTenant{key: tenant.key, name: tenant.name, inserted_at: tenant.inserted_at}
  end

  defp repository_result(operation) do
    operation.()
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error, RuntimeError] ->
      {:error, :repository_unavailable}
  catch
    :exit, _reason -> {:error, :repository_unavailable}
  end
end
