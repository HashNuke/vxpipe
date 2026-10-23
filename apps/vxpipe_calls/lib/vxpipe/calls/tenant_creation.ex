defmodule Vxpipe.Calls.TenantCreation do
  @moduledoc "Authorized browser tenant creation without implicit credentials or resource grants."
  alias Vxpipe.Calls.{PublicId, Repositories, Tenant, UserAuthorization}
  alias Vxpipe.Identity.Principal

  def create(principal, name, options \\ [])

  def create(%Principal{} = principal, name, options) do
    with :ok <- UserAuthorization.authorize_installation(principal, "tenants.write"),
         {:ok, name} <- normalize_name(name),
         {:ok, repository} <- Repositories.fetch(options, :credential_repository) do
      insert(repository, name, 4)
    end
  end

  def create(_principal, _name, _options), do: {:error, :forbidden}

  defp normalize_name(name) when is_binary(name) do
    if String.valid?(name) and String.length(String.trim(name)) in 1..256 and
         not String.contains?(name, <<0>>),
       do: {:ok, String.trim(name)},
       else: {:error, :invalid_tenant_name}
  end

  defp normalize_name(_), do: {:error, :invalid_tenant_name}

  defp insert(_repository, _name, 0), do: {:error, :identifier_generation_exhausted}

  defp insert({module, _} = repository, name, attempts) do
    if Code.ensure_loaded?(module) and function_exported?(module, :create_tenant, 2) do
      tenant = %Tenant{key: PublicId.tenant_key(), name: name, inserted_at: DateTime.utc_now()}

      case Repositories.call(repository, :create_tenant, [tenant]) do
        {:error, :tenant_key_conflict} -> insert(repository, name, attempts - 1)
        result -> result
      end
    else
      {:error, :repository_unavailable}
    end
  end
end
