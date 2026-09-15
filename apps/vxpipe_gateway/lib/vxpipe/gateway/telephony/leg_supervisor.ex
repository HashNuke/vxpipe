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

  @spec start(module(), ConfiguredService.t(), Event.t(), {module(), term()}, function()) ::
          {:ok, pid()} | {:error, term()}
  def start(supervisor \\ __MODULE__, service, event, backend, clock) do
    options = [service: service, event: event, backend: backend, clock: clock]

    case DynamicSupervisor.start_child(supervisor, {Leg, options}) do
      {:ok, leg} -> {:ok, leg}
      {:error, {:already_started, leg}} -> existing_owner(leg, service)
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
      deadline_ms: Keyword.get(runtime_options, :deadline_ms),
      monotonic_clock:
        Keyword.get(runtime_options, :monotonic_clock, fn ->
          System.monotonic_time(:millisecond)
        end),
      media_supervisor: Keyword.get(runtime_options, :media_supervisor, MediaSupervisor),
      usage_clock:
        Keyword.get(runtime_options, :usage_clock, fn -> DateTime.utc_now(:millisecond) end),
      usage_reporter: Keyword.get(runtime_options, :usage_reporter)
    ]

    case DynamicSupervisor.start_child(supervisor, {OutgoingLeg, options}) do
      {:ok, leg} -> {:ok, leg}
      {:error, {:already_started, leg}} -> existing_owner(leg, service)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec lookup(IngressIdentity.t(), String.t()) :: {:ok, pid()} | {:error, :leg_not_found}
  def lookup(identity, provider_call_leg_id) do
    case lookup_entry(identity, provider_call_leg_id) do
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

  @spec dispatch(IngressIdentity.t(), Event.t(), timeout()) :: :ok | {:error, term()}
  def dispatch(identity, %Event{kind: :outgoing} = event, timeout) do
    with {:ok, leg} <- lookup_outgoing(event.leg_id) do
      dispatch_owner({:outgoing, leg}, identity, event, timeout)
    end
  end

  def dispatch(identity, %Event{} = event, timeout) do
    case lookup_entry(identity, event.provider_call_leg_id) do
      {:ok, leg, kind} -> dispatch_owner({kind, leg}, identity, event, timeout)
      {:error, :leg_not_found} -> dispatch_unbound_outgoing(identity, event, timeout)
    end
  end

  @spec stop(IngressIdentity.t(), String.t()) :: :ok
  def stop(identity, provider_call_leg_id) do
    case lookup(identity, provider_call_leg_id) do
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

  defp lookup_entry(identity, provider_call_leg_id) do
    case Registry.lookup(
           Vxpipe.Gateway.Telephony.LegRegistry,
           IngressIdentity.leg_key(identity, provider_call_leg_id)
         ) do
      [{leg, {kind, _service}}] -> {:ok, leg, kind}
      [] -> {:error, :leg_not_found}
    end
  end

  defp dispatch_unbound_outgoing(identity, %Event{leg_id: leg_id} = event, timeout)
       when is_binary(leg_id) do
    with {:ok, leg} <- lookup_outgoing(leg_id) do
      dispatch_owner({:outgoing, leg}, identity, event, timeout)
    end
  end

  defp dispatch_unbound_outgoing(_identity, %Event{}, _timeout), do: {:error, :leg_not_found}

  def dispatch_owner({kind, leg}, identity, event, timeout) do
    if owner_matches?(leg, &(&1.identity == identity)) do
      case kind do
        :incoming -> Leg.dispatch(leg, event, timeout)
        :outgoing -> OutgoingLeg.dispatch(leg, event, timeout)
      end
    else
      {:error, :telephony_leg_mismatch}
    end
  end

  defp existing_owner(leg, service) do
    if owner_matches?(leg, &(&1 == service)),
      do: {:ok, leg},
      else: {:error, :telephony_leg_mismatch}
  end

  defp owner_matches?(leg, matches?) do
    Vxpipe.Gateway.Telephony.LegRegistry
    |> Registry.keys(leg)
    |> Enum.any?(fn key ->
      case Registry.lookup(Vxpipe.Gateway.Telephony.LegRegistry, key) do
        [{^leg, {_kind, %ConfiguredService{} = service}}] -> matches?.(service)
        _missing -> false
      end
    end)
  end
end
