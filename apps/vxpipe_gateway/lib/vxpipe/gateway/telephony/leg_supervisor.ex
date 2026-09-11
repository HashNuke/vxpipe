defmodule Vxpipe.Gateway.Telephony.LegSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Telephony.{Event, OutboundLegRequest}

  alias Vxpipe.Gateway.Telephony.{
    ConfiguredService,
    IngressIdentity,
    Leg,
    MediaSupervisor,
    OutgoingLeg
  }

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

  @spec start_outgoing(
          String.t(),
          OutboundLegRequest.t(),
          ConfiguredService.t(),
          GenServer.server()
        ) :: {:ok, pid()} | {:error, term()}
  def start_outgoing(leg_id, request, service, media_admission) do
    start_outgoing(__MODULE__, leg_id, request, service, media_admission, [])
  end

  @spec start_outgoing(
          GenServer.server(),
          String.t(),
          OutboundLegRequest.t(),
          ConfiguredService.t(),
          GenServer.server()
        ) :: {:ok, pid()} | {:error, term()}
  def start_outgoing(supervisor, leg_id, request, service, media_admission) do
    start_outgoing(supervisor, leg_id, request, service, media_admission, [])
  end

  @spec start_outgoing(
          GenServer.server(),
          String.t(),
          OutboundLegRequest.t(),
          ConfiguredService.t(),
          GenServer.server(),
          keyword()
        ) :: {:ok, pid()} | {:error, term()}
  def start_outgoing(supervisor, leg_id, request, service, media_admission, runtime_options) do
    options = [
      leg_id: leg_id,
      request: request,
      service: service,
      media_admission: media_admission,
      media_supervisor: Keyword.get(runtime_options, :media_supervisor, MediaSupervisor)
    ]

    case DynamicSupervisor.start_child(supervisor, {OutgoingLeg, options}) do
      {:ok, leg} -> {:ok, leg}
      {:error, {:already_started, leg}} -> {:ok, leg}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec lookup(atom(), String.t(), String.t()) :: {:ok, pid()} | {:error, :leg_not_found}
  def lookup(provider, service, provider_call_leg_id) do
    case lookup_entry(provider, service, provider_call_leg_id) do
      {:ok, leg, _kind} -> {:ok, leg}
      {:error, :leg_not_found} = error -> error
    end
  end

  @spec lookup_outgoing(String.t()) :: {:ok, pid()} | {:error, :leg_not_found}
  def lookup_outgoing(leg_id) do
    case Registry.lookup(Vxpipe.Gateway.Telephony.LegRegistry, {:outgoing, leg_id}) do
      [{leg, _value}] -> {:ok, leg}
      [] -> {:error, :leg_not_found}
    end
  end

  @spec dispatch(String.t(), Event.t(), timeout()) :: :ok | {:error, term()}
  def dispatch(_service, %Event{kind: :outgoing} = event, timeout) do
    with {:ok, leg} <- lookup_outgoing(event.leg_id) do
      OutgoingLeg.dispatch(leg, event, timeout)
    end
  end

  def dispatch(service, %Event{} = event, timeout) do
    case lookup_entry(event.provider, service, event.provider_call_leg_id) do
      {:ok, leg, :outgoing} -> OutgoingLeg.dispatch(leg, event, timeout)
      {:ok, leg, _incoming} -> Leg.dispatch(leg, event, timeout)
      {:error, :leg_not_found} = error -> error
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

  @spec stop_outgoing(String.t()) :: :ok
  def stop_outgoing(leg_id) do
    case lookup_outgoing(leg_id) do
      {:ok, leg} ->
        _result = DynamicSupervisor.terminate_child(__MODULE__, leg)
        :ok

      {:error, :leg_not_found} ->
        :ok
    end
  end

  defp lookup_entry(provider, service, provider_call_leg_id) do
    case Registry.lookup(Vxpipe.Gateway.Telephony.LegRegistry, {
           provider,
           service,
           provider_call_leg_id
         }) do
      [{leg, kind}] -> {:ok, leg, kind}
      [] -> {:error, :leg_not_found}
    end
  end
end
