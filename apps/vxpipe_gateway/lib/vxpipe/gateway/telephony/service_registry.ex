defmodule Vxpipe.Gateway.Telephony.ServiceRegistry do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.ConfiguredService

  @derive {Inspect, only: [:enabled?]}
  @enforce_keys [:enabled?, :services]
  defstruct @enforce_keys

  @type t :: %__MODULE__{enabled?: boolean(), services: %{String.t() => ConfiguredService.t()}}

  @spec init!(keyword()) :: t()
  def init!(options) when is_list(options) do
    options = Keyword.validate!(options, enabled: false, services: [])

    if Keyword.fetch!(options, :enabled) do
      %__MODULE__{enabled?: true, services: services!(Keyword.fetch!(options, :services))}
    else
      %__MODULE__{enabled?: false, services: %{}}
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

  defp services!(services) when is_list(services) do
    Enum.reduce(services, %{}, fn options, configured ->
      case ConfiguredService.new(options) do
        {:ok, service} ->
          ingress_key = service.identity.ingress_key

          if Map.has_key?(configured, ingress_key) do
            raise ArgumentError, "duplicate telephony service ingress_key"
          else
            Map.put(configured, ingress_key, service)
          end

        {:error, :invalid_telephony_service_configuration} ->
          raise ArgumentError, "invalid telephony service configuration"
      end
    end)
  end

  defp services!(_invalid), do: raise(ArgumentError, "telephony services must be a list")
end
