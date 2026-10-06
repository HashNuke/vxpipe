defmodule Vxpipe.Calls.CallSpecCredentials do
  @moduledoc false

  alias Vxpipe.CallEngine.{CallSpec, Error, ResolvedCallPlan}
  alias Vxpipe.CallEngine.CallSpec.CapabilityRequirements

  alias Vxpipe.Calls.{
    CallSpecRevision,
    ProviderAuth,
    ProviderCredential,
    ProviderCredentials,
    Repositories,
    ResolvedProviderCredential,
    TelephonyPlanBindings,
    TelephonyServices
  }

  def with_active(%CallSpecRevision{} = revision, options, operation) do
    with {:ok, call_spec} <-
           CallSpec.new(revision.source,
             resource_id: revision.call_spec_id,
             revision: revision.revision
           ) do
      with_active(call_spec, revision.tenant_key, options, operation)
    end
  end

  def with_active(
        %CallSpecRevision{} = revision,
        %ResolvedCallPlan{} = plan,
        options,
        operation
      ) do
    with true <- revision.tenant_key == plan.tenant_id,
         {:ok, call_spec} <-
           CallSpec.new(revision.source,
             resource_id: revision.call_spec_id,
             revision: revision.revision
           ) do
      with_active_capabilities(
        call_spec,
        revision.tenant_key,
        options,
        fn ->
          TelephonyPlanBindings.with_active(plan, options, operation)
        end,
        plan.credential_bindings
      )
    else
      false -> unavailable(["tenant_id"])
      error -> error
    end
  end

  def with_active(%CallSpec{} = call_spec, tenant_key, options, operation) do
    with_active_capabilities(call_spec, tenant_key, options, fn ->
      with_active_services(call_spec, tenant_key, options, operation)
    end)
  end

  defp with_active_capabilities(call_spec, tenant_key, options, operation, bindings \\ nil) do
    requirements =
      call_spec
      |> CapabilityRequirements.credentials()
      |> Enum.map(fn {selection, path} ->
        requirement =
          authoring_requirement(
            %{
              provider: selection.provider,
              name: selection.credential_name,
              path: path
            },
            options
          )

        if is_map(bindings) do
          Map.put(
            requirement,
            :identity,
            Map.get(bindings, {selection.provider, selection.credential_name})
          )
        else
          requirement
        end
      end)

    case requirements do
      [] ->
        operation.()

      [first | _] ->
        case Repositories.fetch(options, :provider_credential_repository) do
          {:ok, repository} ->
            case Repositories.call(repository, :with_active, [tenant_key, requirements, operation]) do
              {:error, {:provider_credential_unavailable, path}} -> unavailable(path)
              {:error, {:provider_service_forbidden, path}} -> forbidden(path)
              result -> result
            end

          {:error, _reason} ->
            unavailable(first.path)
        end
    end
  end

  def pin(%CallSpec{} = call_spec, %ResolvedCallPlan{} = plan, options) do
    call_spec
    |> CapabilityRequirements.credentials()
    |> Enum.reduce_while({:ok, %{}}, fn {selection, path}, {:ok, bindings} ->
      case resolve(plan.tenant_id, selection, options) do
        {:ok, resolved} ->
          identity = ProviderCredential.binding_identity(resolved.credential)

          {:cont,
           {:ok, Map.put(bindings, {selection.provider, selection.credential_name}, identity)}}

        {:error, _reason} ->
          {:halt, unavailable(path)}
      end
    end)
    |> case do
      {:ok, bindings} -> {:ok, %{plan | credential_bindings: bindings}}
      error -> error
    end
  end

  def check(%CallSpec{} = call_spec, tenant_key, options) do
    with :ok <- check_capabilities(call_spec, tenant_key, options) do
      call_spec
      |> service_requirements()
      |> Enum.reduce_while(:ok, fn requirement, :ok ->
        case TelephonyServices.resolve(tenant_key, requirement.name, options) do
          {:ok, snapshot} ->
            if ProviderCredential.allowed_owner?(
                 snapshot.credential.credential,
                 Keyword.get(options, :service_authoring_owner)
               ),
               do: {:cont, :ok},
               else: {:halt, forbidden(requirement.path)}

          {:error, _reason} ->
            {:halt, unavailable(requirement.path)}
        end
      end)
    end
  end

  defp check_capabilities(call_spec, tenant_key, options) do
    call_spec
    |> CapabilityRequirements.credentials()
    |> Enum.reduce_while(:ok, fn {selection, path}, :ok ->
      case resolve(tenant_key, selection, options) do
        {:ok, _credential} -> {:cont, :ok}
        {:error, :provider_service_forbidden} -> {:halt, forbidden(path)}
        {:error, _reason} -> {:halt, unavailable(path)}
      end
    end)
  end

  defp with_active_services(call_spec, tenant_key, options, operation) do
    case service_requirements(call_spec, Keyword.get(options, :outbound_number_required?, false)) do
      [] ->
        operation.()

      [first | _] = requirements ->
        requirements = Enum.map(requirements, &authoring_requirement(&1, options))

        case TelephonyServices.with_active(tenant_key, requirements, options, operation) do
          {:error, {:provider_service_forbidden, path}} ->
            forbidden(path)

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

  defp service_requirements(call_spec, require_outbound \\ false) do
    call_spec.participants
    |> Enum.flat_map(fn
      {ref, %{connection: %{service: service}}} when is_binary(service) ->
        [
          %{
            name: service,
            path: ["participants", ref, "connection", "service"],
            outbound_required?:
              require_outbound and call_spec.direction == :outgoing and
                call_spec.entry_caller == ref
          }
        ]

      _local ->
        []
    end)
    |> Enum.sort_by(&{&1.name, not &1.outbound_required?, &1.path})
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
         true <- ProviderCredential.available_to?(credential, tenant_key),
         true <- credential.provider == selection.provider,
         true <- credential.name == selection.credential_name and credential.status == :active,
         :ok <- ProviderAuth.validate(credential.provider, credential.auth_kind, resolved.payload) do
      if ProviderCredential.allowed_owner?(
           credential,
           Keyword.get(options, :service_authoring_owner)
         ),
         do: {:ok, resolved},
         else: {:error, :provider_service_forbidden}
    else
      _unavailable -> {:error, :provider_credential_unavailable}
    end
  end

  defp authoring_requirement(requirement, options) do
    case Keyword.get(options, :service_authoring_owner) do
      nil -> requirement
      owner -> Map.put(requirement, :allowed_owner, owner)
    end
  end

  defp forbidden(path) do
    {:error,
     Error.new(
       :provider_service_forbidden,
       "This author cannot reference a platform-only service.",
       details: %{"path" => path}
     )}
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
