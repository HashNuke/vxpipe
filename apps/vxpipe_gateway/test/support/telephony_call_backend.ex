defmodule Vxpipe.Gateway.TestTelephonyCallBackend do
  use Agent

  @behaviour Vxpipe.Gateway.Telephony.CallIngressBackend

  alias Vxpipe.CallEngine.CallDefinition.TransferPolicy
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.{CallVariables, ToolVisibility}
  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.Calls.{PreparedCall, TelephonyAdmissionClaim}

  def start_link(options) do
    Agent.start_link(fn ->
      %{
        claim: claim(),
        observer: Keyword.fetch!(options, :observer),
        operations: [],
        activation_failure?: Keyword.get(options, :activation_failure?, false),
        claimed?: false,
        start_failure?: Keyword.get(options, :start_failure?, false)
      }
    end)
  end

  def backend(agent), do: {__MODULE__, agent}
  def claim(agent), do: Agent.get(agent, & &1.claim)
  def operations(agent), do: Agent.get(agent, &Enum.reverse(&1.operations))

  @impl true
  def claim_incoming(agent, identity, event) do
    Agent.get_and_update(agent, fn state ->
      operation =
        {:claim_incoming, identity.scope, identity.service_id, event.provider_call_leg_id}

      if state.claimed? do
        {{:duplicate, state.claim}, %{state | operations: [operation | state.operations]}}
      else
        {{:ok, state.claim},
         %{state | claimed?: true, operations: [operation | state.operations]}}
      end
    end)
  end

  @impl true
  def start_incoming(agent, claim) do
    operation(agent, {:start_incoming, claim.call.id})

    if Agent.get(agent, & &1.start_failure?) do
      {:error, :room_start_failed}
    else
      {:ok, room_snapshot()}
    end
  end

  @impl true
  def activate_incoming(agent, _identity, claim, room, leg) do
    operation(agent, {:activate_incoming, claim.call.id, room.incarnation_id, leg})

    if Agent.get(agent, & &1.activation_failure?) do
      {:error, :command_rejected}
    else
      {:ok, :test_activation}
    end
  end

  @impl true
  def mark_incoming_started(agent, claim, incarnation_id, started_at) do
    operation(agent, {:mark_incoming_started, claim.call.id, incarnation_id, started_at})

    started = %{
      claim
      | call: %{
          claim.call
          | state: :running,
            incarnation_id: incarnation_id,
            started_at: started_at
        }
    }

    Agent.update(agent, &%{&1 | claim: started})
    {:ok, started}
  end

  @impl true
  def mark_incoming_failed(agent, claim, reason) do
    operation(agent, {:mark_incoming_failed, claim.call.id, reason})
    failed = %{claim | call: %{claim.call | state: :failed, terminal_reason: reason}}
    Agent.update(agent, &%{&1 | claim: failed})
    {:ok, failed}
  end

  @impl true
  def handle_live_event(agent, claim, _activation, event) do
    operation(agent, {:handle_live_event, claim.call.id, event.kind, event.provider_event_id})
    send(Agent.get(agent, & &1.observer), {:test_live_telephony_event, event})
    :ok
  end

  defp operation(agent, value) do
    Agent.update(agent, &%{&1 | operations: [value | &1.operations]})
  end

  defp claim do
    plan = resolved_plan()

    %TelephonyAdmissionClaim{
      call: %PreparedCall{
        id: "30000000-0000-4000-8000-000000000003",
        tenant_key: "AAAAAAAAAAAAAAAA",
        definition_id: "50000000-0000-4000-8000-000000000005",
        definition_revision: 1,
        schema_version: "20260911.03",
        participant_routes: %{},
        entry_caller: "caller",
        entry_receiver: "assistant",
        initial_variables: %{},
        plan: plan,
        plan_digest: :crypto.hash(:sha256, :erlang.term_to_binary(plan)),
        state: :admitting,
        room_id: plan.room_id,
        created_at: ~U[2026-09-11 10:40:00.000000Z],
        started_at: nil,
        ended_at: nil,
        incarnation_id: nil,
        terminal_reason: nil
      },
      participant_ref: "caller",
      participant_id: "part_phone-caller",
      provider: :telnyx,
      service: "primary-phone",
      provider_event_id: "event-incoming-1",
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      accepted_at: ~U[2026-09-11 10:40:00.000000Z]
    }
  end

  defp resolved_plan do
    %ResolvedCallPlan{
      definition_id: "50000000-0000-4000-8000-000000000005",
      definition_revision: 1,
      schema_version: "20260911.03",
      tenant_id: "AAAAAAAAAAAAAAAA",
      actor_id: "actor_phone",
      call_id: "30000000-0000-4000-8000-000000000003",
      room_id: "60000000-0000-4000-8000-000000000006",
      transport: :telephony,
      entry_caller: "caller",
      entry_receiver: "assistant",
      opening_audio: nil,
      media_policy: ResolvedCallPlan.MediaPolicy.inherit(),
      participants: %{},
      transfer_policy: %TransferPolicy{attempt_timeout_ms: 30_000},
      call_variables: %CallVariables{},
      tool_visibility: ToolVisibility.hidden(),
      max_duration_ms: 60_000
    }
  end

  defp room_snapshot do
    %RoomSnapshot{
      tenant_id: "AAAAAAAAAAAAAAAA",
      room_id: "60000000-0000-4000-8000-000000000006",
      incarnation_id: "rinc_phone-1",
      lifecycle: :open,
      created_by_actor_id: "actor_phone",
      created_by_command_id: "cmd_phone-start"
    }
  end
end
