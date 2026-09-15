defmodule Vxpipe.Calls.DefinitionCredentials do
  @moduledoc false

  alias Vxpipe.CallEngine.{CallDefinition, Error}
  alias Vxpipe.CallEngine.CallDefinition.CapabilityRequirements

  alias Vxpipe.Calls.{
    DefinitionRevision,
    ProviderAuth,
    ProviderCredentials,
    Repositories,
    ResolvedProviderCredential,
    TelephonyServices
  }

  def with_active(%DefinitionRevision{} = revision, options, operation) do
    with {:ok, definition} <-
           CallDefinition.new(revision.source,
             resource_id: revision.definition_id,
             revision: revision.revision
           ) do
      with_active(definition, revision.tenant_key, options, operation)
    end
  end

  def with_active(%CallDefinition{} = definition, tenant_key, options, operation) do
    with_active_capabilities(definition, tenant_key, options, fn ->
      with_active_services(definition, tenant_key, options, operation)
    end)
  end

  defp with_active_capabilities(definition, tenant_key, options, operation) do
    requirements =
      definition
      |> CapabilityRequirements.credentials()
      |> Enum.map(fn {selection, path} ->
        %{provider: selection.provider, name: selection.credential_name, path: path}
      end)

    case requirements do
      [] ->
        operation.()

      [first | _] ->
        case Repositories.fetch(options, :provider_credential_repository) do
          {:ok, repository} ->
            case Repositories.call(repository, :with_active, [tenant_key, requirements, operation]) do
              {:error, {:provider_credential_unavailable, path}} -> unavailable(path)
              result -> result
            end

          {:error, _reason} ->
            unavailable(first.path)
        end
    end
  end

  def check(%CallDefinition{} = definition, tenant_key, options) do
    with :ok <- check_capabilities(definition, tenant_key, options) do
      definition
      |> service_requirements()
      |> Enum.reduce_while(:ok, fn requirement, :ok ->
        case TelephonyServices.resolve(tenant_key, requirement.name, options) do
          {:ok, _private_snapshot} -> {:cont, :ok}
          {:error, _reason} -> {:halt, unavailable(requirement.path)}
        end
      end)
    end
  end

  defp check_capabilities(definition, tenant_key, options) do
    definition
    |> CapabilityRequirements.credentials()
    |> Enum.reduce_while(:ok, fn {selection, path}, :ok ->
      case resolve(tenant_key, selection, options) do
        {:ok, _credential} -> {:cont, :ok}
        {:error, _reason} -> {:halt, unavailable(path)}
      end
    end)
  end

  defp with_active_services(definition, tenant_key, options, operation) do
    case service_requirements(definition) do
      [] ->
        operation.()

      [first | _] = requirements ->
        case TelephonyServices.with_active(tenant_key, requirements, options, operation) do
          {:error, {:provider_credential_unavailable, path}} ->
            unavailable(path)

          {:error, reason}
          when reason in [:repository_unavailable, :telephony_services_unavailable] ->
            unavailable(first.path)

          result ->
            result
        end
    end
  end

  defp service_requirements(definition) do
    definition.participants
    |> Enum.flat_map(fn
      {ref, %{connection: %{service: service}}} when is_binary(service) ->
        [%{name: service, path: ["participants", ref, "connection", "service"]}]

      _local ->
        []
    end)
    |> Enum.sort_by(&{&1.name, &1.path})
    |> Enum.uniq_by(& &1.name)
  end

  def resolve(tenant_key, selection, options) do
    with {:ok, %ResolvedProviderCredential{} = resolved} <-
           ProviderCredentials.resolve(
             tenant_key,
             selection.provider,
             selection.credential_name,
             options
           ),
         credential <- resolved.credential,
         true <- credential.tenant_key == tenant_key and credential.provider == selection.provider,
         true <- credential.name == selection.credential_name and credential.status == :active,
         :ok <- ProviderAuth.validate(credential.provider, credential.auth_kind, resolved.payload) do
      {:ok, resolved}
    else
      _unavailable -> {:error, :provider_credential_unavailable}
    end
  end

  defp unavailable(path) do
    {:error,
     Error.new(
       :provider_credential_unavailable,
       "The selected tenant provider credential is unavailable.",
       details: %{"path" => path}
     )}
  end
end
