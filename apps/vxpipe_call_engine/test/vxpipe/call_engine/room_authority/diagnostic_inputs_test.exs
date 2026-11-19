defmodule Vxpipe.CallEngine.RoomAuthority.DiagnosticInputsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.{ResolvedCallPlan, RoomAuthority}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Capabilities, Participant}
  alias Vxpipe.CallEngine.RoomAuthority.{State, ParticipantTransfer.Runtime}
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.Archive.Recorder

  test "two human STT inputs are paged without selected-agent or private plan data" do
    state = %{state() | text_capability: nil}
    assert {:reply, {:ok, page}, ^state} = query(state, nil, 1)

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
    refute Map.has_key?(page, :agent)
    refute :erlang.term_to_binary(page) =~ "private-plan-content"

    assert {:reply, {:ok, %{sources: [%{connection_id: "b"}], next_cursor: nil}}, ^state} =
             query(state, page.next_cursor, 1)
  end

  test "response-side STS and agent transfers do not change surviving human input identity" do
    state = state()
    assert {:reply, {:ok, before}, ^state} = query(state)
    sts = struct(CapabilitySelection, kind: :speech_to_speech)

    changed =
      put_in(
        state.participant_transfer_runtime.plan.participants["agent"].capabilities.speech_to_speech,
        sts
      )

    changed = %{
      changed
      | text_capability: %{participant_id: "another-agent", pid: self()},
        speech_to_speech_capability: %{pid: self()},
        speech_to_speech_runtime: %{},
        participant_ids: MapSet.new(["human-a", "human-b"])
    }

    assert {:reply, {:ok, ^before}, ^changed} = query(changed)
  end

  test "only admitted present unheld human STT bindings are candidates" do
    base = state()

    for state <- [
          put_in(base.connections["a"].speech_to_text, nil),
          put_in(base.connections["a"].admission, :transfer_preparation),
          put_in(base.connections["a"].role, :agent),
          put_in(base.participant_transfer_runtime.plan.participants["human-a"].kind, :agent),
          %{base | held_participant_ids: MapSet.new(["human-a"])},
          %{base | participant_ids: MapSet.new(["human-b"])}
        ] do
      assert {:reply, {:ok, %{sources: [%{connection_id: "b"}]}}, ^state} = query(state)
    end

    native = %{base | connections: %{}}
    assert {:reply, {:ok, %{sources: []}}, ^native} = query(native)
  end

  test "exact connection reads revalidate source replacement and survive page movement" do
    state = state()
    assert {:reply, {:ok, %{sources: [source]}}, ^state} = query(state, {:connection, "b"}, 1)
    moved = %{state | connections: Map.delete(state.connections, "a")}
    assert {:reply, {:ok, %{sources: [^source]}}, ^moved} = query(moved, {:connection, "b"}, 1)
    replacement = start_supervised!({Agent, fn -> :replacement end})
    rebound = put_in(moved.connections["b"].speech_to_text.capability, replacement)

    assert {:reply, {:ok, %{sources: [%{capability: ^replacement}]}}, ^rebound} =
             query(rebound, {:connection, "b"}, 1)

    replaced = put_in(moved.connections["b"].speech_to_text.capability, nil)
    assert {:reply, {:ok, %{sources: []}}, ^replaced} = query(replaced, {:connection, "b"}, 1)
  end

  test "query bounds and room readiness or identity fail closed" do
    base = state()

    for {cursor, limit} <- [
          {nil, 0},
          {nil, 33},
          {false, 1},
          {String.duplicate("x", 257), 1},
          {{:connection, "a"}, 2},
          {{:connection, ""}, 1}
        ] do
      assert {:reply, {:error, :invalid_query}, ^base} = query(base, cursor, limit)
    end

    for state <- [
          %{base | startup_ready?: false},
          %{base | outgoing_admission: %{status: :pending}},
          put_in(base.participant_transfer_runtime.plan.tenant_id, "other"),
          put_in(base.participant_transfer_runtime.plan.room_id, "other"),
          put_in(base.snapshot.lifecycle, :ended),
          %{base | participant_transfer_runtime: nil}
        ] do
      assert {:reply, {:error, :unavailable}, ^state} = query(state)
    end
  end

  defp query(state, cursor \\ nil, limit \\ 16),
    do:
      RoomAuthority.handle_call({:diagnostic_inputs, cursor, limit}, {self(), make_ref()}, state)

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
