defmodule Vxpipe.CallEngine.RoomAuthority.DiagnosticSourcesTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.{ResolvedCallPlan, RoomAuthority}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Capabilities, Participant}
  alias Vxpipe.CallEngine.RoomAuthority.{State, ParticipantTransfer.Runtime}
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.Archive.Recorder

  test "room discovery pages current human STT bindings without plan content" do
    state = state()

    assert {:reply, {:ok, page}, ^state} =
             RoomAuthority.handle_call({:diagnostic_sources, nil, 1}, {self(), make_ref()}, state)

    assert page.identity == %{
             tenant_id: "tenant",
             call_id: "call",
             room_id: "room",
             incarnation_id: "incarnation"
           }

    assert [%{connection_id: "a", participant_id: "human-a", capability: capability}] =
             page.sources

    assert capability == self()
    assert page.next_cursor == "a"
    assert page.agent.kind == :agent
    assert page.agent.participant_id == "agent"
    assert page.agent.prompt == nil
    refute :erlang.term_to_binary(page) =~ "private-plan-content"

    assert {:reply, {:ok, next}, ^state} =
             RoomAuthority.handle_call(
               {:diagnostic_sources, page.next_cursor, 1},
               {self(), make_ref()},
               state
             )

    assert [%{connection_id: "b", participant_id: "human-b"}] = next.sources
    assert next.next_cursor == nil
  end

  test "inactive, private, held and non-human sources are excluded" do
    state = state()
    state = put_in(state.connections["a"].admission, :transfer_preparation)
    state = %{state | held_participant_ids: MapSet.new(["human-b"])}
    assert {:reply, {:ok, %{sources: [], next_cursor: nil}}, ^state} = query(state)
  end

  test "native STS, non-LLM, absent agent and unready rooms cannot admit observers" do
    base = state()
    sts = struct(CapabilitySelection, kind: :speech_to_speech)

    mixed =
      put_in(
        base.participant_transfer_runtime.plan.participants["agent"].capabilities.speech_to_speech,
        sts
      )

    for state <- [
          %{base | speech_to_speech_capability: %{pid: self()}},
          %{base | speech_to_speech_runtime: %{}},
          %{base | text_capability: nil},
          %{base | startup_ready?: false},
          %{base | participant_ids: MapSet.new(["human-a", "human-b"])},
          mixed
        ] do
      assert {:reply, {:error, :unsupported_call}, ^state} = query(state)
    end
  end

  test "query bounds and call ownership fail closed" do
    state = state()

    for {cursor, limit} <- [{nil, 0}, {nil, 33}, {false, 1}, {String.duplicate("x", 257), 1}] do
      assert {:reply, {:error, :invalid_query}, ^state} =
               RoomAuthority.handle_call(
                 {:diagnostic_sources, cursor, limit},
                 {self(), make_ref()},
                 state
               )
    end

    wrong = put_in(state.participant_transfer_runtime.plan.tenant_id, "other")
    assert {:reply, {:error, :unsupported_call}, ^wrong} = query(wrong)
  end

  defp query(state),
    do: RoomAuthority.handle_call({:diagnostic_sources, nil, 16}, {self(), make_ref()}, state)

  defp state do
    agent =
      struct(Participant,
        participant_id: "agent",
        kind: :agent,
        prompt: "private-plan-content",
        capabilities: %Capabilities{
          model_inference:
            struct(CapabilitySelection,
              kind: :model_inference,
              options: %{"private" => "private-plan-content"}
            )
        }
      )

    humans =
      for suffix <- ["a", "b"],
          into: %{},
          do:
            {"human-" <> suffix,
             struct(Participant, participant_id: "human-" <> suffix, kind: :human)}

    plan =
      struct(ResolvedCallPlan,
        tenant_id: "tenant",
        room_id: "room",
        call_id: "call",
        participants: Map.put(humans, "agent", agent)
      )

    snapshot = %Snapshot{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      lifecycle: :open,
      created_by_actor_id: "actor",
      created_by_command_id: "command"
    }

    state = State.new(%Recorder{port: nil, participant_activations: %{}}, snapshot, %{})

    connections =
      for suffix <- ["a", "b"],
          into: %{},
          do:
            {suffix,
             %{
               participant_id: "human-" <> suffix,
               role: :human,
               admission: :main,
               speech_to_text: %{capability: self()}
             }}

    %{
      state
      | text_capability: %{participant_id: "agent", pid: self()},
        participant_ids: MapSet.new(["agent", "human-a", "human-b"]),
        participant_transfer_runtime: %Runtime{plan: plan, startup_options: []},
        connections: connections
    }
  end
end
