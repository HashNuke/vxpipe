defmodule Vxpipe.Gateway.TestTelephonyCallBackend do
  use Agent

  @behaviour Vxpipe.Gateway.Telephony.CallIngressBackend

  alias Vxpipe.CallEngine.CallSpec.TransferPolicy
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.{CallVariables, ToolVisibility}
  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.Calls.{PreparedCall, TelephonyAdmissionClaim}

  alias Vxpipe.Gateway.Telephony.{
    IncomingLegActivation,
    IncomingLegActivationResult,
    IncomingLegIdentity
  }

  def start_link(options) do
    Agent.start_link(fn ->
      %{
        claim: claim(),
        activation: Keyword.get(options, :activation, :test_activation),
        observer: Keyword.fetch!(options, :observer),
        usage_options: Keyword.take(options, [:usage_reporter, :usage_clock]),
        operations: [],
        activation_failure?: Keyword.get(options, :activation_failure?, false),
        claimed?: Keyword.get(options, :claimed?, false),
        room_owner: Keyword.get(options, :room_owner),
        cancel_failures: Keyword.get(options, :cancel_failures, 0),
        end_event_failure?: Keyword.get(options, :end_event_failure?, false),
        end_blocked?: Keyword.get(options, :end_blocked?, false),
        activation_blocked?: Keyword.get(options, :activation_blocked?, false),
        bind_decision: Keyword.get(options, :bind_decision, :admit),
        started_failure?: Keyword.get(options, :started_failure?, false),
        start_failure?: Keyword.get(options, :start_failure?, false)
      }
    end)
  end

  def backend(agent), do: {__MODULE__, agent}
  def claim(agent), do: Agent.get(agent, & &1.claim)
  def put_activation(agent, activation), do: Agent.update(agent, &%{&1 | activation: activation})
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
  def start_incoming(agent, claim, _service) do
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

    block_answer(agent)

    if Agent.get(agent, & &1.activation_failure?) do
      {:error, :command_rejected}
    else
      {:ok, Agent.get(agent, & &1.activation)}
    end
  end

  @impl true
  def start_incoming(agent, claim, service, _owner, _token) do
    case start_incoming(agent, claim, service) do
      {:ok, room} ->
        owner = Agent.get(agent, & &1.room_owner)
        {:ok, room, if(is_pid(owner), do: Process.monitor(owner), else: nil)}

      error ->
        error
    end
  end

  @impl true
  def bind_incoming(agent, claim, incarnation) do
    operation(agent, {:bind_incoming, claim.call.id, incarnation})

    case Agent.get(agent, & &1.bind_decision) do
      decision when decision in [:admit, :cancel] ->
        {:ok, decision, %{claim | call: %{claim.call | incarnation_id: incarnation}}}

      :error ->
        {:error, :call_admission_unavailable}
    end
  end

  @impl true
  def identify_incoming(agent, service, claim, room, leg) do
    case Agent.get(agent, & &1.activation) do
      %IncomingLegActivationResult{} = activation ->
        {:ok,
         %IncomingLegIdentity{
           binding: activation.binding,
           service: service,
           usage: activation.usage
         }}

      _custom ->
        # The unit backend uses a fixed claim with a per-test configured service.
        claim = %{claim | service: service.identity.service_id}

        IncomingLegActivation.identify(
          service,
          claim,
          room.incarnation_id,
          leg,
          Agent.get(agent, & &1.usage_options)
        )
    end
  end

  @impl true
  def prepare_incoming(agent, identity) do
    binding = identity.binding
    operation(agent, {:activate_incoming, binding.call_id, binding.incarnation_id, binding.leg})
    {:ok, Agent.get(agent, & &1.activation)}
  end

  @impl true
  def submit_incoming(agent, prepared) do
    block_answer(agent)

    if Agent.get(agent, & &1.activation_failure?),
      do: {:error, :command_rejected, prepared},
      else: {:ok, prepared}
  end

  @impl true
  def release_incoming(agent, claim, _token) do
    operation(agent, {:release_incoming, claim.call.id, claim.call.incarnation_id})
    :ok
  end

  @impl true
  def cancel_incoming(agent, claim, _token, reason) do
    operation(agent, {:cancel_incoming, claim.call.id, claim.call.incarnation_id, reason})
    send(Agent.get(agent, & &1.observer), {:incoming_room_cancel_requested, reason})

    Agent.get_and_update(agent, fn state ->
      if state.cancel_failures > 0,
        do: {{:error, :room_unavailable}, %{state | cancel_failures: state.cancel_failures - 1}},
        else: {:ok, state}
    end)
  end

  @impl true
  def end_incoming(agent, _service, event, _activation, reason) do
    send(
      Agent.get(agent, & &1.observer),
      {:incoming_end_requested, event.provider_call_control_id, reason}
    )

    if Agent.get(agent, & &1.end_blocked?) do
      send(Agent.get(agent, & &1.observer), {:incoming_end_pending, self()})

      receive do
        :release_incoming_end -> {:error, :command_rejected}
      end
    else
      :ok
    end
  end

  defp block_answer(agent) do
    if Agent.get(agent, & &1.activation_blocked?) do
      send(Agent.get(agent, & &1.observer), {:incoming_answer_pending, self()})

      receive do
        :release_incoming_answer -> :ok
      end
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

    if Agent.get(agent, & &1.started_failure?) do
      {:error, :call_unavailable}
    else
      Agent.update(agent, &%{&1 | claim: started})
      {:ok, started}
    end
  end

  @impl true
  def mark_incoming_failed(agent, claim, reason) do
    operation(agent, {:mark_incoming_failed, claim.call.id, reason})
    failed = %{claim | call: %{claim.call | state: :failed, terminal_reason: reason}}
    Agent.update(agent, &%{&1 | claim: failed})
    {:ok, failed}
  end

  @impl true
  def handle_live_event(agent, claim, _activation, source, event) do
    operation(agent, {:handle_live_event, claim.call.id, event.kind, event.provider_event_id})
    send(Agent.get(agent, & &1.observer), {:test_live_telephony_event, event, source})

    Agent.get_and_update(agent, fn state ->
      if event.kind == :ended and state.end_event_failure?,
        do: {{:error, :room_unavailable}, %{state | end_event_failure?: false}},
        else: {:ok, state}
    end)
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
        call_spec_id: "50000000-0000-4000-8000-000000000005",
        call_spec_revision: 1,
        schema_version: "20260913.01",
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
      service_id: "10000000-0000-4000-8000-000000000001",
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
      call_spec_id: "50000000-0000-4000-8000-000000000005",
      call_spec_revision: 1,
      schema_version: "20260913.01",
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
