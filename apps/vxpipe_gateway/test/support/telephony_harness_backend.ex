defmodule Vxpipe.Gateway.TelephonyHarnessBackend do
  @moduledoc false

  use Agent

  @behaviour Vxpipe.Gateway.Telephony.CallIngressBackend

  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls.TelephonyAdmissionClaim
  alias Vxpipe.Gateway.CallAdmission

  alias Vxpipe.Gateway.Telephony.{
    IncomingLegActivationResult,
    ConfiguredService,
    IngressIdentity,
    MediaBinding
  }

  def start_link(options) do
    Agent.start_link(fn ->
      %{
        available?: true,
        claim: Keyword.fetch!(options, :claim),
        claimed?: false,
        operations: [],
        runtime_options: Keyword.fetch!(options, :runtime_options)
      }
    end)
  end

  def backend(agent), do: {__MODULE__, agent}

  def available?(agent), do: Agent.get(agent, & &1.available?)

  def operations(agent) do
    Agent.get(agent, &Enum.reverse(&1.operations))
  end

  def make_storage_unavailable(agent) do
    Agent.update(agent, &%{&1 | available?: false})
  end

  @impl true
  def claim_incoming(agent, %IngressIdentity{} = identity, %Event{} = event) do
    Agent.get_and_update(agent, fn state ->
      state = record(state, {:claim_incoming, event.provider_event_id})

      cond do
        not state.available? ->
          {{:error, :repository_unavailable}, state}

        not matches_claim?(state.claim, identity, event) ->
          {{:error, :route_unavailable}, state}

        state.claimed? ->
          {{:duplicate, state.claim}, state}

        true ->
          {{:ok, state.claim}, %{state | claimed?: true}}
      end
    end)
  end

  @impl true
  def start_incoming(agent, %TelephonyAdmissionClaim{} = claim, %ConfiguredService{} = service) do
    runtime_options = operation(agent, {:start_incoming, claim.call.id})
    CallAdmission.start_incoming(runtime_options, claim, service)
  end

  @impl true
  def activate_incoming(
        agent,
        %ConfiguredService{} = service,
        %TelephonyAdmissionClaim{} = claim,
        %RoomSnapshot{} = room,
        leg
      ) do
    runtime_options = operation(agent, {:activate_incoming, claim.call.id, leg})
    CallAdmission.activate_incoming(runtime_options, service, claim, room, leg)
  end

  @impl true
  def mark_incoming_started(agent, claim, incarnation_id, started_at) do
    Agent.get_and_update(agent, fn state ->
      state = record(state, {:mark_incoming_started, incarnation_id, started_at})

      if state.available? do
        call = %{
          claim.call
          | state: :running,
            incarnation_id: incarnation_id,
            started_at: started_at
        }

        started = %{claim | call: call}
        {{:ok, started}, %{state | claim: started}}
      else
        {{:error, :repository_unavailable}, state}
      end
    end)
  end

  @impl true
  def mark_incoming_failed(agent, claim, reason) do
    Agent.get_and_update(agent, fn state ->
      state = record(state, {:mark_incoming_failed, reason})

      if state.available? do
        failed = %{claim | call: %{claim.call | state: :failed, terminal_reason: reason}}
        {{:ok, failed}, %{state | claim: failed}}
      else
        {{:error, :repository_unavailable}, state}
      end
    end)
  end

  @impl true
  def handle_live_event(
        agent,
        %TelephonyAdmissionClaim{} = claim,
        %IncomingLegActivationResult{binding: %MediaBinding{}} = activation,
        source,
        %Event{} = event
      ) do
    runtime_options = operation(agent, {:handle_live_event, event.kind})

    CallAdmission.handle_live_event(
      runtime_options,
      claim,
      activation,
      source,
      event
    )
  end

  defp operation(agent, value) do
    Agent.get_and_update(agent, fn state ->
      {state.runtime_options, record(state, value)}
    end)
  end

  defp record(state, value), do: %{state | operations: [value | state.operations]}

  defp matches_claim?(claim, identity, event) do
    identity.scope == {:tenant, claim.call.tenant_key} and
      identity.service_id == claim.service and
      identity.provider == claim.provider and
      identity.provider_connection_id == claim.provider_connection_id and
      event.provider == claim.provider and
      event.provider_event_id == claim.provider_event_id and
      event.provider_connection_id == claim.provider_connection_id and
      event.provider_call_control_id == claim.provider_call_control_id and
      event.provider_call_leg_id == claim.provider_call_leg_id and
      event.provider_call_session_id == claim.provider_call_session_id
  end
end
