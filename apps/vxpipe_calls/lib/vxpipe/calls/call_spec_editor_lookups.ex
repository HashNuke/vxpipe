defmodule Vxpipe.Calls.CallSpecEditorLookups do
  @moduledoc "Installation- or user-authorized, secret-free choices for the portable call spec editor."
  alias Vxpipe.CallEngine.RemoteMCP.ConfiguredNames

  alias Vxpipe.Calls.{
    EffectiveServiceBindings,
    InstallationOperator,
    OperatorAdministration,
    OperatorTelephonyApplications,
    ProviderAuth,
    ProviderCredential,
    Repositories,
    TelephonyService,
    Tenant,
    UserAuthorization
  }

  alias Vxpipe.Identity.Principal, as: UserPrincipal

  def list(%UserPrincipal{} = principal, tenant, options) when is_list(options) do
    privileged = UserAuthorization.platform_authoring_allowed?(principal)

    with :ok <- ProviderAuth.tenant_key(tenant),
         :ok <- UserAuthorization.authorize_tenant(principal, "call_specs.read", tenant),
         {:ok, bindings} <- EffectiveServiceBindings.list(tenant, options),
         {:ok, telephony} <- list_member_services(tenant, options, privileged),
         {:ok, applications} <- list_member_applications(tenant, options, privileged),
         {:ok, integrations} <- ConfiguredNames.list(tenant) do
      names =
        bindings.bindings
        |> then(fn all ->
          if privileged, do: all, else: Enum.filter(all, &(&1.source == :tenant))
        end)
        |> Enum.group_by(& &1.provider, & &1.name)
        |> Map.new(fn {provider, names} -> {provider, Enum.sort(names)} end)

      {:ok,
       %{
         tenant: bindings.tenant,
         credential_names: names,
         telephony_services:
           (Enum.map(
              telephony.telephony_services,
              &%{key: &1.name, name: &1.name, provider: &1.provider}
            ) ++
              Enum.map(
                applications.applications,
                &%{key: &1.name, name: &1.name, provider: "telnyx"}
              ))
           |> Enum.uniq_by(& &1.key)
           |> Enum.sort_by(& &1.name),
         mcp_integrations: integrations,
         truncated: telephony.truncated or applications.truncated
       }}
    else
      {:error, :invalid_tenant_key} = error -> error
      error -> error
    end
  end

  def list(%InstallationOperator{grant: :installation_operator} = authority, tenant, options) do
    with {:ok, bindings} <- EffectiveServiceBindings.list(tenant, options),
         {:ok, telephony} <- OperatorAdministration.list_services(authority, tenant, options),
         {:ok, applications} <- OperatorTelephonyApplications.list(authority, tenant, options),
         {:ok, integrations} <- ConfiguredNames.list(tenant) do
      names =
        bindings.bindings
        |> Enum.group_by(& &1.provider, & &1.name)
        |> Map.new(fn {provider, names} -> {provider, Enum.sort(names)} end)

      {:ok,
       %{
         tenant: bindings.tenant,
         credential_names: names,
         telephony_services:
           (Enum.map(
              telephony.telephony_services,
              &%{key: &1.name, name: &1.name, provider: &1.provider}
            ) ++
              Enum.map(
                applications.applications,
                &%{key: &1.name, name: &1.name, provider: "telnyx"}
              ))
           |> Enum.uniq_by(& &1.key)
           |> Enum.sort_by(& &1.name),
         mcp_integrations: integrations,
         truncated: telephony.truncated or applications.truncated
       }}
    end
  end

  def list(_authority, _tenant, _options), do: {:error, :installation_operator_required}

  # Tenant-pinned, secret-free telephony metadata for authorized spec readers.
  # Unlike OperatorAdministration.list_services/3 this never requires
  # `tenant_services.read` and never returns credentials, ingress keys, or
  # secrets. Repository rows are validated and pinned to the requested tenant
  # before projecting only `{key, name, provider}`. Members without
  # `call_specs.use_platform_services` only see tenant-owned services; privileged
  # authors may also select tenant-pinned platform-owned services they are
  # allowed to reference in specs.
  defp list_member_services(tenant_key, options, privileged?) do
    with {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         {:ok, {tenant, credentials, services, truncated}} <-
           Repositories.call(repository, :list_services, [tenant_key]),
         true <- is_boolean(truncated),
         {:ok, visible} <-
           filter_member_service_directory(tenant_key, tenant, credentials, services, privileged?) do
      {:ok, %{telephony_services: visible, truncated: truncated}}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :service_directory_unavailable}
    end
  end

  defp list_member_applications(tenant_key, options, privileged?) do
    with {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         :ok <- applications_supported?(repository),
         {:ok, {%Tenant{key: ^tenant_key} = _owner, services, routes, truncated}} <-
           Repositories.call(repository, :list_telephony_applications, [tenant_key]),
         true <-
           is_list(services) and length(services) <= 100 and
             Enum.all?(services, &editor_application?(&1, tenant_key, true)),
         true <-
           is_list(routes) and length(routes) <= 500 and
             Enum.all?(routes, &member_route?(&1, tenant_key)),
         true <- is_boolean(truncated) do
      visible = Enum.filter(services, &editor_application?(&1, tenant_key, privileged?))

      {:ok, %{applications: Enum.map(visible, &Map.take(&1, [:id, :name])), truncated: truncated}}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :telephony_services_unavailable}
    end
  end

  defp applications_supported?({module, _context}) do
    if function_exported?(module, :list_telephony_applications, 2),
      do: :ok,
      else: {:error, :telephony_services_unavailable}
  end

  defp filter_member_service_directory(
         tenant_key,
         %Tenant{key: tenant_key},
         credentials,
         services,
         privileged?
       )
       when is_list(credentials) and is_list(services) and is_boolean(privileged?) do
    credential_ids =
      credentials
      |> Enum.filter(&valid_member_credential?(&1, tenant_key))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    credentials_valid? = MapSet.size(credential_ids) == length(credentials)

    tenant_pinned? =
      Enum.all?(services, fn
        %TelephonyService{tenant_key: ^tenant_key} -> true
        _foreign -> false
      end)

    # Members without `call_specs.use_platform_services` stay on tenant-owned
    # rows. Privileged authors may also select tenant-pinned platform-owned
    # rows they are allowed to reference. Foreign-tenant rows still fail closed
    # via `tenant_pinned?`.
    allowed_owners =
      if privileged?,
        do: [nil, {:tenant, tenant_key}, :platform],
        else: [nil, {:tenant, tenant_key}]

    visible =
      Enum.filter(services, fn
        %TelephonyService{tenant_key: ^tenant_key} = service ->
          service.credential_owner in allowed_owners

        _foreign ->
          false
      end)

    services_valid? =
      Enum.all?(visible, fn
        %TelephonyService{credential_owner: :platform} = service ->
          platform_service_valid?(service)

        %TelephonyService{
          provider: "telnyx",
          credential_name: "telnyx",
          credential_id: nil,
          public_key: nil
        } = service ->
          TelephonyService.validate(service) == :ok

        %TelephonyService{provider: provider, credential_id: id}
        when provider in ["telnyx", "twilio"] ->
          MapSet.member?(credential_ids, id)

        _invalid ->
          false
      end)

    if credentials_valid? and tenant_pinned? and services_valid?,
      do: {:ok, visible},
      else: {:error, :service_directory_unavailable}
  end

  defp filter_member_service_directory(
         _tenant_key,
         _tenant,
         _credentials,
         _services,
         _privileged?
       ),
       do: {:error, :service_directory_unavailable}

  defp platform_service_valid?(%TelephonyService{provider: provider} = service)
       when provider in ["telnyx", "twilio"] do
    TelephonyService.validate(service) == :ok
  end

  defp platform_service_valid?(_service), do: false

  defp valid_member_credential?(
         %ProviderCredential{
           tenant_key: tenant_key,
           provider: provider,
           name: name,
           auth_kind: auth_kind
         },
         tenant_key
       ) do
    ProviderAuth.binding(tenant_key, provider, name) == :ok and
      valid_member_auth_kind?(provider, auth_kind)
  end

  defp valid_member_credential?(_credential, _tenant_key), do: false

  defp valid_member_auth_kind?(provider, auth_kind) do
    case Vxpipe.Providers.Registry.resolve_capability(provider, :credential) do
      {:ok, schema} -> schema.auth_kind() == auth_kind
      {:error, _unsupported} -> false
    end
  end

  defp editor_application?(service, tenant_key, true) do
    member_application?(service, tenant_key) or privileged_application?(service, tenant_key)
  end

  defp editor_application?(service, tenant_key, _privileged?) do
    member_application?(service, tenant_key)
  end

  defp privileged_application?(
         %TelephonyService{
           tenant_key: tenant,
           provider: "telnyx",
           credential_name: "telnyx"
         } = service,
         tenant
       ),
       do: TelephonyService.validate(service) == :ok

  defp privileged_application?(_service, _tenant), do: false

  defp member_application?(
         %TelephonyService{
           tenant_key: tenant_key,
           provider: "telnyx",
           credential_name: "telnyx",
           credential_id: nil,
           public_key: nil,
           credential_owner: owner
         } = service,
         tenant_key
       ) do
    owner in [nil, {:tenant, tenant_key}] and TelephonyService.validate(service) == :ok
  end

  defp member_application?(_service, _tenant), do: false

  defp member_route?(
         %{
           tenant_key: tenant,
           service: name,
           number: number,
           call_spec_id: id,
           call_spec_name: title,
           call_spec_revision: revision,
           participant_ref: participant,
           ambiguous: ambiguous
         },
         tenant
       ) do
    TelephonyService.identifier(name) == :ok and
      is_binary(number) and byte_size(number) in 2..16 and
      is_binary(id) and byte_size(id) in 1..128 and
      is_binary(title) and is_integer(revision) and revision > 0 and
      is_binary(participant) and byte_size(participant) in 1..128 and is_boolean(ambiguous)
  end

  defp member_route?(_route, _tenant), do: false
end
