defmodule Vxpipe.Calls.OperatorTelephonyApplications do
  @moduledoc "Installation-authorized configuration of tenant Telnyx applications."

  alias Vxpipe.Calls.{
    InstallationOperator,
    ProviderAuth,
    PublicId,
    Repositories,
    TelephonyService,
    TelephonyServices,
    Tenant
  }

  @application_fields [:id, :name, :provider_connection_id, :outbound_number]
  @route_fields [
    :number,
    :call_spec_id,
    :call_spec_name,
    :call_spec_revision,
    :participant_ref,
    :ambiguous
  ]
  @edit_fields ["provider_connection_id", "outbound_number"]

  def create(authority, tenant, attributes, options \\ [])

  def create(%InstallationOperator{grant: :installation_operator}, tenant, attributes, options) do
    with :ok <- input(attributes, ["name" | @edit_fields]),
         {:ok, service} <-
           TelephonyServices.register(
             tenant,
             Map.merge(attributes, %{
               "provider" => "telnyx",
               "credential_name" => "telnyx",
               "ingress_key" => "telnyx-#{PublicId.uuid()}"
             }),
             options
           ),
         true <- application?(service, tenant) do
      {:ok, Map.take(service, @application_fields)}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :telephony_service_write_failed}
    end
  end

  def create(_authority, _tenant, _attributes, _options),
    do: {:error, :installation_operator_required}

  def update(authority, tenant, id, attributes, options \\ [])

  def update(
        %InstallationOperator{grant: :installation_operator},
        tenant,
        id,
        attributes,
        options
      ) do
    with :ok <- ProviderAuth.tenant_key(tenant),
         :ok <- input(attributes, @edit_fields),
         true <-
           is_binary(id) and
             Regex.match?(
               ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
               id
             ),
         {:ok, repository} <- Repositories.fetch(options, :telephony_service_repository),
         {:ok, service} <-
           Repositories.call(repository, :update_application, [tenant, id, attributes]),
         true <- application?(service, tenant) and service.id == id do
      {:ok, Map.take(service, @application_fields)}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_telephony_service}
    end
  end

  def update(_authority, _tenant, _id, _attributes, _options),
    do: {:error, :installation_operator_required}

  def list(authority, tenant, options \\ [])

  def list(%InstallationOperator{grant: :installation_operator}, tenant, options) do
    with :ok <- ProviderAuth.tenant_key(tenant),
         {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         {:ok, {%Tenant{key: ^tenant} = owner, services, routes, truncated}} <-
           Repositories.call(repository, :list_telephony_applications, [tenant]),
         true <-
           is_list(services) and length(services) <= 100 and
             Enum.all?(services, &application?(&1, tenant)),
         true <-
           is_list(routes) and length(routes) <= 500 and Enum.all?(routes, &route?(&1, tenant)),
         true <- is_boolean(truncated) do
      by_service = Enum.group_by(routes, & &1.service, &Map.take(&1, @route_fields))

      {:ok,
       %{
         tenant: %{key: owner.key, name: owner.name},
         applications:
           Enum.map(services, fn service ->
             service
             |> Map.take(@application_fields)
             |> Map.put(:published_routes, Map.get(by_service, service.name, []))
           end),
         truncated: truncated
       }}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :telephony_services_unavailable}
    end
  end

  def list(_authority, _tenant, _options), do: {:error, :installation_operator_required}

  defp input(attributes, allowed) when is_map(attributes) and map_size(attributes) > 0 do
    if Enum.all?(Map.keys(attributes), &(&1 in allowed)),
      do: :ok,
      else: {:error, :invalid_telephony_service}
  end

  defp input(_attributes, _allowed), do: {:error, :invalid_telephony_service}

  defp application?(
         %TelephonyService{
           tenant_key: tenant,
           provider: "telnyx",
           credential_name: "telnyx",
           credential_id: nil,
           public_key: nil
         } = service,
         tenant
       ),
       do: TelephonyService.validate(service) == :ok

  defp application?(_service, _tenant), do: false

  defp route?(
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

  defp route?(_route, _tenant), do: false
end
