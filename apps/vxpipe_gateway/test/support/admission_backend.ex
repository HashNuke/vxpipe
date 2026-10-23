defmodule Vxpipe.Gateway.TestAdmissionBackend do
  use Agent

  alias Vxpipe.CallEngine.Participant.Snapshot, as: ParticipantSnapshot
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.{CallVariables, ToolVisibility}
  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.Calls.{AdmissionClaim, IssuedJoinToken, PreparedCall, Principal}

  def start_link(options) do
    Agent.start_link(fn ->
      %{
        api_key: Keyword.fetch!(options, :api_key),
        room: Keyword.get(options, :room, room_snapshot()),
        existing_call?: Keyword.get(options, :existing_call?, false),
        join_token: Keyword.fetch!(options, :join_token),
        observer: Keyword.fetch!(options, :observer),
        participant_failure?: Keyword.get(options, :participant_failure?, false),
        projection_failure?: Keyword.get(options, :projection_failure?, false),
        start_failure?: Keyword.get(options, :start_failure?, false),
        transfer_pending?: Keyword.get(options, :transfer_pending?, false),
        operations: []
      }
    end)
  end

  def backend(agent), do: {__MODULE__, agent}

  def calls_options(agent) do
    [
      credential_repository: {__MODULE__, agent},
      call_repository: {__MODULE__, agent},
      now: ~U[2026-09-09 12:00:00.000000Z],
      join_token_generator: fn -> Agent.get(agent, & &1.join_token) end
    ]
  end

  def fetch_api_key_by_digest(agent, digest) do
    Agent.get(agent, fn state ->
      if digest == :crypto.hash(:sha256, state.api_key) do
        {:ok,
         %{
           id: "fixture-key",
           tenant_key: tenant_key(),
           scopes: MapSet.new([:calls]),
           revoked_at: nil
         }}
      else
        {:error, :not_found}
      end
    end)
  end

  def fetch_call(_agent, tenant, id) do
    if tenant == tenant_key() and id == call_id(),
      do: {:ok, prepared_call()},
      else: {:error, :not_found}
  end

  def issue_join_token(agent, tenant, id, participant, token) do
    operation(agent, {:issue_join_token, tenant, id, participant})
    {:ok, token}
  end

  def operations(agent), do: Agent.get(agent, &Enum.reverse(&1.operations))

  def authenticate(agent, tenant_key, secret) do
    operation(agent, {:authenticate, tenant_key})

    Agent.get(agent, fn state ->
      if tenant_key == tenant_key() and secret == state.api_key do
        {:ok,
         %Principal{
           tenant_key: tenant_key,
           api_key_id: "10000000-0000-4000-8000-000000000001",
           scopes: MapSet.new([:calls])
         }}
      else
        {:error, :invalid_api_key}
      end
    end)
  end

  def prepare(agent, principal, participant_key, initial_variables, ttl_seconds) do
    operation(
      agent,
      {:prepare, principal.tenant_key, participant_key, initial_variables, ttl_seconds}
    )

    if principal.tenant_key == tenant_key() and participant_key == participant_key() do
      {:ok, prepared_call(), issued_token(agent, ttl_seconds)}
    else
      {:error, :route_unavailable}
    end
  end

  def issue_token(agent, principal, call_id, participant_key, ttl_seconds) do
    operation(agent, {:issue_token, principal.tenant_key, call_id, participant_key, ttl_seconds})

    if principal.tenant_key == tenant_key() and call_id == call_id() and
         participant_key == participant_key() do
      {:ok, issued_token(agent, ttl_seconds)}
    else
      {:error, :not_found}
    end
  end

  def claim_token(agent, secret, expected_scope) do
    operation(agent, {:claim_token, expected_scope})

    Agent.get(agent, fn state ->
      if secret == state.join_token and expected_scope == expected_scope() do
        {:ok, admission_claim(state)}
      else
        {:error, :token_scope_mismatch}
      end
    end)
  end

  def start_call(agent, claim) do
    operation(agent, {:start_call, claim.call.id})

    state = Agent.get(agent, & &1)

    cond do
      state.transfer_pending? ->
        {:transfer_pending, %{participant_id: "part_test-support", kind: :human}}

      state.existing_call? ->
        {:joined, participant_snapshot(state.room)}

      state.start_failure? ->
        {:error, :room_start_failed}

      true ->
        room = state.room

        case mark_started(agent, claim, room.incarnation_id, DateTime.utc_now()) do
          {:ok, started} ->
            if state.participant_failure?,
              do: {:started, room, started},
              else: {:ok, room, participant_snapshot(room), started}

          {:error, reason} ->
            {:admission_error, reason}
        end
    end
  end

  def release_admission(agent, claim) do
    operation(agent, {:release_admission, claim.token_id})
    state = Agent.get(agent, & &1)
    send(state.observer, {:test_admission_released, claim.token_id})
    :ok
  end

  def mark_started(agent, claim, incarnation_id, started_at) do
    operation(agent, {:mark_started, claim.call.id, incarnation_id, started_at})
    state = Agent.get(agent, & &1)
    send(state.observer, {:test_admission_started, incarnation_id, started_at})

    if state.projection_failure?,
      do: {:error, :projection_failed},
      else:
        {:ok,
         %{
           claim.call
           | state: :running,
             started_at: started_at,
             incarnation_id: incarnation_id,
             gateway_cleanup_required: Map.get(state, :managed_cleanup?, false),
             incarnation_binding_verified: true
         }}
  end

  def mark_failed(agent, claim, reason) do
    operation(agent, {:mark_failed, claim.call.id, reason})
    state = Agent.get(agent, & &1)
    send(state.observer, {:test_admission_failed, reason})
    {:ok, claim.call}
  end

  def tenant_key, do: "AAAAAAAAAAAAAAAA"
  def participant_key, do: "20000000-0000-4000-8000-000000000002"
  def call_id, do: "30000000-0000-4000-8000-000000000003"

  defp expected_scope do
    %{tenant_key: tenant_key(), call_id: call_id(), participant_key: participant_key()}
  end

  defp operation(agent, operation) do
    Agent.update(agent, fn state -> %{state | operations: [operation | state.operations]} end)
  end

  defp issued_token(agent, ttl_seconds) do
    secret = Agent.get(agent, & &1.join_token)
    issued_at = ~U[2026-09-09 12:00:00.000000Z]
    ttl_seconds = ttl_seconds || 300

    %IssuedJoinToken{
      id: "40000000-0000-4000-8000-000000000004",
      secret: secret,
      tenant_key: tenant_key(),
      call_id: call_id(),
      participant_key: participant_key(),
      participant_ref: "caller",
      issued_at: issued_at,
      expires_at: DateTime.add(issued_at, ttl_seconds, :second)
    }
  end

  defp admission_claim(state) do
    call = admitted_call(state.existing_call? or state.transfer_pending?)
    call = %{call | room_id: state.room.room_id, plan: %{call.plan | room_id: state.room.room_id}}

    call =
      if call.state == :running,
        do: %{call | incarnation_id: state.room.incarnation_id},
        else: call

    %AdmissionClaim{
      call: call,
      token_id: "40000000-0000-4000-8000-000000000004",
      participant_key: participant_key(),
      participant_ref: "caller",
      participant_id: "part_test-caller",
      accepted_at: ~U[2026-09-09 12:00:10.000000Z]
    }
  end

  defp admitted_call(true) do
    %{
      prepared_call()
      | state: :running,
        started_at: ~U[2026-09-09 12:00:05.000000Z],
        incarnation_id: "rinc_test-admission"
    }
  end

  defp admitted_call(false), do: %{prepared_call() | state: :admitting}

  defp prepared_call do
    plan = resolved_plan()

    %PreparedCall{
      id: call_id(),
      tenant_key: tenant_key(),
      call_spec_id: "50000000-0000-4000-8000-000000000005",
      call_spec_revision: 1,
      schema_version: "20260913.01",
      participant_routes: %{participant_key() => "caller"},
      entry_caller: "caller",
      entry_receiver: "assistant",
      initial_variables: %{"private" => %{"sentinel" => "never-return-this"}},
      plan: plan,
      plan_digest: :crypto.hash(:sha256, :erlang.term_to_binary(plan)),
      state: :prepared,
      room_id: plan.room_id,
      created_at: ~U[2026-09-09 12:00:00.000000Z],
      started_at: nil,
      ended_at: nil,
      incarnation_id: nil,
      terminal_reason: nil
    }
  end

  defp resolved_plan do
    %ResolvedCallPlan{
      call_spec_id: "50000000-0000-4000-8000-000000000005",
      call_spec_revision: 1,
      schema_version: "20260913.01",
      tenant_id: tenant_key(),
      actor_id: "actor_test-caller",
      call_id: call_id(),
      room_id: "60000000-0000-4000-8000-000000000006",
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "assistant",
      opening_audio: nil,
      media_policy: Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy.inherit(),
      participants: %{
        "caller" => %{
          participant_id: "part_test-caller",
          connection: %{service: :web, mode: :receive, admission: :start_call}
        }
      },
      transfer_policy: %Vxpipe.CallEngine.CallSpec.TransferPolicy{
        attempt_timeout_ms: 30_000
      },
      call_variables: %CallVariables{},
      tool_visibility: ToolVisibility.hidden(),
      max_duration_ms: 60_000
    }
  end

  defp room_snapshot do
    %RoomSnapshot{
      tenant_id: tenant_key(),
      room_id: "60000000-0000-4000-8000-000000000006",
      incarnation_id: "rinc_test-admission",
      lifecycle: :open,
      created_by_actor_id: "actor_test-caller",
      created_by_command_id: "cmd_test-admission"
    }
  end

  defp participant_snapshot(room) do
    %ParticipantSnapshot{
      tenant_id: room.tenant_id,
      room_id: room.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: "part_test-caller",
      role: :human,
      state: :joined,
      created_by_actor_id: "actor_test-caller",
      created_by_command_id: "cmd_test-participant"
    }
  end
end
