defmodule Vxpipe.Gateway.Telephony.ServiceRegistry do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.ServiceReference
  alias Vxpipe.Calls.{TelephonyService, TelephonyServices}
  alias Vxpipe.Gateway.Telephony.ConfiguredService

  @derive {Inspect, only: [:enabled?]}
  @enforce_keys [:enabled?, :public_base_url, :repository_options, :adapters]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          enabled?: boolean(),
          public_base_url: String.t() | nil,
          repository_options: keyword(),
          adapters: map()
        }

  def init!(options) do
    options =
      validate_options!(options,
        enabled: false,
        public_base_url: nil,
        telephony_service_repository: nil,
        adapters: %{}
      )

    repository_options =
      options
      |> Keyword.take([:telephony_service_repository])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    %__MODULE__{
      enabled?: Keyword.fetch!(options, :enabled),
      public_base_url: Keyword.fetch!(options, :public_base_url),
      repository_options: repository_options,
      adapters: Keyword.fetch!(options, :adapters)
    }
  end

  @spec fetch(t(), String.t()) ::
          {:ok, ConfiguredService.t()} | {:error, :disabled | :service_not_found}
  def fetch(%__MODULE__{enabled?: false}, _ingress), do: {:error, :disabled}

  def fetch(%__MODULE__{} = registry, ingress) do
    with {:ok, %TelephonyService{} = candidate} <-
           TelephonyServices.fetch_by_ingress(ingress, registry.repository_options),
         {:ok, snapshot} <-
           TelephonyServices.resolve(
             candidate.tenant_key,
             candidate.name,
             registry.repository_options
           ),
         true <- snapshot.service.ingress_key == ingress and candidate.ingress_key == ingress,
         true <-
           TelephonyServices.reference(snapshot.service) == TelephonyServices.reference(candidate),
         {:ok, service} <- configure(registry, snapshot) do
      {:ok, service}
    else
      _unavailable -> {:error, :service_not_found}
    end
  rescue
    _exception -> {:error, :service_not_found}
  catch
    :exit, _reason -> {:error, :service_not_found}
  end

  @spec fetch_for_tenant(t(), String.t(), String.t(), ServiceReference.t() | nil) ::
          {:ok, ConfiguredService.t()} | {:error, :disabled | :service_not_found}
  def fetch_for_tenant(%__MODULE__{enabled?: false}, _name, _tenant, _reference),
    do: {:error, :disabled}

  def fetch_for_tenant(
        %__MODULE__{} = registry,
        name,
        tenant,
        %ServiceReference{tenant_id: tenant, name: name} = reference
      ) do
    with {:ok, snapshot} <- TelephonyServices.resolve(tenant, name, registry.repository_options),
         true <- TelephonyServices.reference(snapshot.service) == reference,
         {:ok, service} <- configure(registry, snapshot) do
      {:ok, service}
    else
      _unavailable -> {:error, :service_not_found}
    end
  rescue
    _exception -> {:error, :service_not_found}
  catch
    :exit, _reason -> {:error, :service_not_found}
  end

  def fetch_for_tenant(%__MODULE__{}, _name, _tenant, _reference),
    do: {:error, :service_not_found}

  defp configure(registry, snapshot) do
    ConfiguredService.from_snapshot(snapshot, registry.public_base_url, registry.adapters)
  end

  defp validate_options!(options, allowed) do
    case Keyword.validate(options, allowed) do
      {:ok, options} -> options
      {:error, _keys} -> raise ArgumentError, "invalid telephony configuration"
    end
  end
end
