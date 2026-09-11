defmodule Vxpipe.Gateway.Telephony.ServiceRegistry do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.ConfiguredService

  @derive {Inspect, only: [:enabled?]}
  @enforce_keys [:enabled?, :services, :services_by_scope]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          enabled?: boolean(),
          services: %{String.t() => ConfiguredService.t()},
          services_by_scope: %{
            {:application | {:tenant, String.t()}, String.t()} => ConfiguredService.t()
          }
        }

  @spec init!(keyword()) :: t()
  def init!(options) when is_list(options) do
    options = Keyword.validate!(options, enabled: false, services: [])

    if Keyword.fetch!(options, :enabled) do
      {services, services_by_scope} = services!(Keyword.fetch!(options, :services))

      %__MODULE__{
        enabled?: true,
        services: services,
        services_by_scope: services_by_scope
      }
    else
      %__MODULE__{enabled?: false, services: %{}, services_by_scope: %{}}
    end
  end

  @spec fetch(t(), String.t()) ::
          {:ok, ConfiguredService.t()} | {:error, :disabled | :service_not_found}
  def fetch(%__MODULE__{enabled?: false}, _ingress_key), do: {:error, :disabled}

  def fetch(%__MODULE__{services: services}, ingress_key) do
    case Map.fetch(services, ingress_key) do
      {:ok, service} -> {:ok, service}
      :error -> {:error, :service_not_found}
    end
  end

  @spec fetch_for_tenant(t(), String.t(), String.t()) ::
          {:ok, ConfiguredService.t()} | {:error, :disabled | :service_not_found}
  def fetch_for_tenant(%__MODULE__{enabled?: false}, _service_id, _tenant_key),
    do: {:error, :disabled}

  def fetch_for_tenant(%__MODULE__{services_by_scope: services}, service_id, tenant_key)
      when is_binary(service_id) and is_binary(tenant_key) do
    case Map.fetch(services, {{:tenant, tenant_key}, service_id}) do
      {:ok, service} -> {:ok, service}
      :error -> fetch_application_service(services, service_id)
    end
  end

  def fetch_for_tenant(%__MODULE__{}, _service_id, _tenant_key),
    do: {:error, :service_not_found}

  defp services!(services) when is_list(services) do
    Enum.reduce(services, {%{}, %{}}, fn options, {by_ingress, by_scope} ->
      case ConfiguredService.new(options) do
        {:ok, service} ->
          ingress_key = service.identity.ingress_key
          scoped_key = {service.identity.scope, service.identity.service_id}

          ensure_unique!(by_ingress, ingress_key, "duplicate telephony service ingress_key")

          ensure_unique!(
            by_scope,
            scoped_key,
            "duplicate telephony service id within scope"
          )

          {Map.put(by_ingress, ingress_key, service), Map.put(by_scope, scoped_key, service)}

        {:error, :invalid_telephony_service_configuration} ->
          raise ArgumentError, "invalid telephony service configuration"
      end
    end)
  end

  defp services!(_invalid), do: raise(ArgumentError, "telephony services must be a list")

  defp fetch_application_service(services, service_id) do
    case Map.fetch(services, {:application, service_id}) do
      {:ok, service} -> {:ok, service}
      :error -> {:error, :service_not_found}
    end
  end

  defp ensure_unique!(map, key, message) do
    if Map.has_key?(map, key), do: raise(ArgumentError, message)
  end
end
