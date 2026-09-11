defmodule Vxpipe.Gateway.Telephony.LegSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.{IngressIdentity, Leg}

  def start_link(_options) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec start(module(), IngressIdentity.t(), Event.t(), {module(), term()}, function()) ::
          {:ok, pid()} | {:error, term()}
  def start(supervisor \\ __MODULE__, identity, event, backend, clock) do
    options = [identity: identity, event: event, backend: backend, clock: clock]

    case DynamicSupervisor.start_child(supervisor, {Leg, options}) do
      {:ok, leg} -> {:ok, leg}
      {:error, {:already_started, leg}} -> {:ok, leg}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec lookup(atom(), String.t(), String.t()) :: {:ok, pid()} | {:error, :leg_not_found}
  def lookup(provider, service, provider_call_leg_id) do
    case Registry.lookup(Vxpipe.Gateway.Telephony.LegRegistry, {
           provider,
           service,
           provider_call_leg_id
         }) do
      [{leg, _value}] -> {:ok, leg}
      [] -> {:error, :leg_not_found}
    end
  end

  @spec dispatch(String.t(), Event.t(), timeout()) :: :ok | {:error, term()}
  def dispatch(service, %Event{} = event, timeout) do
    with {:ok, leg} <- lookup(event.provider, service, event.provider_call_leg_id) do
      Leg.dispatch(leg, event, timeout)
    end
  end

  @spec stop(atom(), String.t(), String.t()) :: :ok
  def stop(provider, service, provider_call_leg_id) do
    case lookup(provider, service, provider_call_leg_id) do
      {:ok, leg} ->
        _result = DynamicSupervisor.terminate_child(__MODULE__, leg)
        :ok

      {:error, :leg_not_found} ->
        :ok
    end
  end
end
