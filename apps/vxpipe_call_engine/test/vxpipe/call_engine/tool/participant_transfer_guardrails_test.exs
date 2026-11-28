defmodule Vxpipe.CallEngine.Tool.ParticipantTransfer.GuardrailsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RoomRegistry
  alias Vxpipe.CallEngine.Tool.{Context, ParticipantTransfer}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding

  defmodule FakeGuardrails do
    use GenServer

    def start_link({activation_id, owner}) do
      GenServer.start_link(__MODULE__, {activation_id, owner})
    end

    @impl true
    def init({activation_id, owner}) do
      Registry.register(RoomRegistry, {:agent_activation, activation_id, :guardrails}, nil)
      {:ok, owner}
    end

    @impl true
    def handle_call({:check, event, proposal, evidence, deadline}, _from, owner) do
      send(owner, {:guardrail_check, event, proposal, evidence, deadline})

      receive do
        {:guardrail_reply, reply} -> {:reply, reply, owner}
      after
        5_000 -> {:reply, {:error, :timeout}, owner}
      end
    end
  end

  defmodule FakeRoomEngine do
    use GenServer

    def start_link({tenant, room, owner, script}) do
      GenServer.start_link(__MODULE__, {tenant, room, owner, script})
    end

    @impl true
    def init({tenant, room, owner, script}) do
      Registry.register(RoomRegistry, {tenant, room}, nil)
      {:ok, %{owner: owner, script: script, verdicts: %{}}}
    end

    @impl true
    def handle_call({:take_transfer_verdict, invocation_id}, _from, state) do
      send(state.owner, {:room_take, invocation_id})

      case Map.get(state.script, :take, :empty) do
        :empty -> {:reply, :empty, state}
        {:ok, entry} -> {:reply, {:ok, entry}, state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end

    def handle_call({:transfer_participant, request}, _from, state) do
      send(state.owner, {:room_transfer, request})

      case Map.get(
             state.script,
             :transfer,
             {:ok, %{"destination" => "billing", "status" => "completed"}}
           ) do
        {:ok, result} -> {:reply, {:ok, result}, state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end

    def handle_call({:bind_transfer_verdict, entry}, _from, state) do
      send(state.owner, {:room_bound, entry})
      {:reply, :ok, state}
    end

    @impl true
    def handle_info({:note_transfer_denial, note}, state) do
      send(state.owner, {:room_denial_note, note})
      {:noreply, state}
    end
  end

  defp ids do
    unique = System.unique_integer([:positive])
    %{activation: "activation-#{unique}", tenant: "tenant-#{unique}", room: "room-#{unique}"}
  end

  defp transfer_binding(%{activation: activation}, digest \\ "digest-t1") do
    %Binding{
      source_call_spec_key: "reception",
      source_participant_id: "part-reception",
      source_activation_id: activation,
      targets: %{
        "billing" => %{
          call_spec_key: "billing",
          participant_id: "part-billing",
          description: "Billing",
          reason_required: false
        }
      },
      guardrails_policy_revision: 4,
      guardrails_policy_digest: digest
    }
  end

  defp context_for(%{tenant: tenant, room: room}, tool_call_id \\ "transfer-1") do
    %Context{
      tenant_id: tenant,
      room_id: room,
      incarnation_id: "incarnation-1",
      agent_participant_id: "part-reception",
      source_participant_id: "caller-1",
      connection_id: "connection-1",
      command_id: "command-1",
      correlation_id: "turn-1",
      agent_request_id: "request-1",
      tool_call_id: tool_call_id,
      source_capability: self(),
      request_origin: :engine
    }
  end

  defp arguments, do: %{"destination" => "billing"}

  defp start_room(test_ids, script \\ %{}) do
    start_supervised!(
      {FakeRoomEngine, {test_ids.tenant, test_ids.room, self(), script}},
      id: {FakeRoomEngine, System.unique_integer([:positive])}
    )
  end

  defp start_guardrails(%{activation: activation}) do
    start_supervised!(
      {FakeGuardrails, {activation, self()}},
      id: {FakeGuardrails, System.unique_integer([:positive])}
    )
  end

  defp bound_entry do
    %{
      invocation_id: "transfer-1",
      verdict: :passed,
      source_activation_id: "activation-1",
      source_participant_id: "part-reception",
      destination_call_spec_key: "billing",
      policy_digest: "digest-t1",
      incarnation_id: "incarnation-1",
      checked_at_ms: System.monotonic_time(:millisecond),
      source: :bound
    }
  end

  test "an expired guarded response cannot reuse a transfer verdict" do
    test_ids = ids()
    start_room(test_ids, %{take: {:ok, bound_entry()}})

    context =
      Map.put(context_for(test_ids), :deadline_ms, System.monotonic_time(:millisecond) - 1)

    assert {:error, :transfer_unavailable} =
             ParticipantTransfer.execute(transfer_binding(test_ids), arguments(), context)

    refute_received {:room_transfer, _}
  end

  test "a fresh native transfer check receives the earlier invocation timeout" do
    alias Vxpipe.CallEngine.Tool.{Invocation, InvocationBinding}

    test_ids = ids()
    start_room(test_ids)
    gate = start_guardrails(test_ids)

    binding = %InvocationBinding{
      name: "transfer",
      conversation_mode: :blocking,
      handler: {:participant_transfer, transfer_binding(test_ids)}
    }

    invocation =
      start_supervised!(
        {Invocation,
         invocation_id: "native-timeout",
         binding: binding,
         arguments: arguments(),
         context: context_for(test_ids),
         reply_to: self(),
         timeout_ms: 500,
         maximum_result_bytes: 1024}
      )

    started = System.monotonic_time(:millisecond)
    assert :ok = Invocation.begin(invocation)

    assert_receive {:guardrail_check, :before_outgoing_transfer, "native-timeout", _, deadline}
    assert deadline in (started + 495)..(System.monotonic_time(:millisecond) + 500)
    send(gate, {:guardrail_reply, {:error, :unavailable}})

    assert_receive {:vxpipe_tool_invocation_finished, ^invocation,
                    %{outcome: {:error, :transfer_unavailable}}}

    refute_received {:room_transfer, _}
  end

  test "no policy digest skips guardrails entirely" do
    test_ids = ids()
    start_room(test_ids)

    assert {:ok, %{effect: :participant_transfer_committed}} =
             ParticipantTransfer.execute(
               transfer_binding(test_ids, nil),
               arguments(),
               context_for(test_ids)
             )

    assert_received {:room_transfer, request}
    assert request.transfer_admission == nil
    refute_received {:room_take, _}
    refute_received {:guardrail_check, _, _, _, _}
  end

  test "a bound verdict is consumed without a fresh evaluation" do
    test_ids = ids()
    start_room(test_ids, %{take: {:ok, bound_entry()}})
    start_guardrails(test_ids)

    assert {:ok, %{effect: :participant_transfer_committed}} =
             ParticipantTransfer.execute(
               transfer_binding(test_ids),
               arguments(),
               context_for(test_ids)
             )

    assert_received {:room_take, "transfer-1"}
    assert_received {:room_transfer, _request}
    refute_received {:guardrail_check, _, _, _, _}
  end

  test "without a bound verdict a fresh passed check binds the exact invocation in the room" do
    test_ids = ids()
    start_room(test_ids)
    start_guardrails(test_ids)
    assert is_pid(find_guardrails(test_ids))

    task =
      Task.async(fn ->
        ParticipantTransfer.execute(
          transfer_binding(test_ids),
          arguments(),
          context_for(test_ids)
        )
      end)

    assert_receive {:guardrail_check, :before_outgoing_transfer, "transfer-1", evidence,
                    _deadline},
                   2_000

    assert evidence["destination"] == "billing"
    send(find_guardrails(test_ids), {:guardrail_reply, :passed})

    assert {:ok, %{effect: :participant_transfer_committed}} = Task.await(task, 5_000)

    assert_receive {:room_take, "transfer-1"}, 2_000
    assert_receive {:room_transfer, request}, 2_000

    assert_receive {:room_bound,
                    %{
                      source: :checked,
                      policy_revision: 4,
                      verdict: :passed,
                      invocation_id: "transfer-1",
                      destination_call_spec_key: "billing"
                    }}

    assert request.transfer_admission == nil
  end

  test "a matched policy denies without announcement, preparation or dial" do
    test_ids = ids()
    start_room(test_ids)
    start_guardrails(test_ids)

    task =
      Task.async(fn ->
        ParticipantTransfer.execute(
          transfer_binding(test_ids),
          arguments(),
          context_for(test_ids)
        )
      end)

    assert_receive {:guardrail_check, :before_outgoing_transfer, "transfer-1", _evidence,
                    _deadline},
                   2_000

    send(
      find_guardrails(test_ids),
      {:guardrail_reply, {:blocked, ["Ask which department the caller needs."]}}
    )

    assert {:error, {:transfer_denied, ["Ask which department the caller needs."]}} =
             Task.await(task, 5_000)

    refute_received {:room_transfer, _}
    assert_receive {:room_denial_note, note}, 2_000
    assert note.tool_call_id == "transfer-1"
    refute Map.has_key?(note, :feedback_digest)
    refute Map.has_key?(note, :messages)
  end

  test "a checker error is distinguishable and performs no transfer" do
    test_ids = ids()
    start_room(test_ids)
    start_guardrails(test_ids)

    task =
      Task.async(fn ->
        ParticipantTransfer.execute(
          transfer_binding(test_ids),
          arguments(),
          context_for(test_ids)
        )
      end)

    assert_receive {:guardrail_check, _, _, _, _}, 2_000
    send(find_guardrails(test_ids), {:guardrail_reply, {:error, :unavailable}})

    assert {:error, :transfer_unavailable} = Task.await(task, 5_000)
    refute_received {:room_transfer, _}
  end

  test "a disallowed destination rejects without guardrail or room work" do
    test_ids = ids()
    start_room(test_ids)
    start_guardrails(test_ids)

    assert {:error, :rejected} =
             ParticipantTransfer.execute(
               transfer_binding(test_ids),
               %{"destination" => "nowhere"},
               context_for(test_ids)
             )

    refute_received {:guardrail_check, _, _, _, _}
    refute_received {:room_take, _}
    refute_received {:room_transfer, _}
  end

  test "questions without a guardrails server fail closed" do
    test_ids = ids()
    start_room(test_ids)

    assert {:error, :transfer_unavailable} =
             ParticipantTransfer.execute(
               transfer_binding(test_ids),
               arguments(),
               context_for(test_ids)
             )

    refute_received {:room_transfer, _}
  end

  defp find_guardrails(%{activation: activation}) do
    GenServer.whereis(
      {:via, Registry, {RoomRegistry, {:agent_activation, activation, :guardrails}}}
    )
  end
end
