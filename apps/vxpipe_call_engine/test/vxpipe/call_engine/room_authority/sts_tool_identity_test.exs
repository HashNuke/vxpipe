defmodule Vxpipe.CallEngine.RoomAuthority.STSToolIdentityTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    ToolCallStarted,
    ToolCallCompleted,
    ToolCallCancelled,
    ToolCallFailed
  }

  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{SpeechToSpeech, State}
  alias Vxpipe.CallEngine.STSInputHandle

  @agent "agent"
  @source "source"

  setup do
    capability = start_supervised!({Vxpipe.CallEngine.STSToolResultReceiver, self()})
    %{capability: capability, state: state(capability)}
  end

  for kind <- [:binary, :reference] do
    test "#{kind} tool-only references stay private through completion", context do
      turn = if unquote(kind) == :binary, do: "private-provider-turn", else: make_ref()
      call = make_ref()
      state = call(context.state, context.capability, call, turn)
      assert_receive {:vxpipe_event, %ToolCallStarted{} = started}
      assert_public_ids(started, call, turn)

      state = SpeechToSpeech.deliver_tool_result(state, context.capability, call, %{"ok" => true})
      assert_receive {:vxpipe_event, %ToolCallCompleted{} = completed}
      assert ids(completed) == ids(started)
      assert_receive {:provider_tool_result, ^call, %{"ok" => true}}
      assert state.sts_tool_calls == %{}
      assert SpeechToSpeech.deliver_tool_result(state, context.capability, call, %{}) == state
      refute_received {:provider_tool_result, _, _}
      refute_received {:vxpipe_event, _}
    end
  end

  test "tools in an active audio turn retain that public turn's IDs", context do
    turn = make_ref()
    state = SpeechToSpeech.handle_turn_started(context.state, context.capability, @agent, turn)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{} = speech}
    call = make_ref()
    state = call(state, context.capability, call, turn)
    assert_receive {:vxpipe_event, %ToolCallStarted{} = tool}
    assert tool.command_id == speech.command_id
    assert tool.correlation_id == speech.correlation_id
    assert_public_ids(tool, call, turn)
    _state = SpeechToSpeech.handle_tool_cancelled(state, context.capability, @agent, call)
    assert_receive {:vxpipe_event, %ToolCallCancelled{} = cancelled}
    assert ids(cancelled) == ids(tool)
  end

  test "active duplicates neither overwrite an invocation nor publish again", context do
    call = make_ref()
    turn = make_ref()
    state = call(context.state, context.capability, call, turn)
    assert_receive {:vxpipe_event, %ToolCallStarted{}}
    assert call(state, context.capability, call, make_ref()) == state
    refute_received {:vxpipe_event, _}
    refute_received {:provider_tool_result, _, _}
  end

  test "concurrent tool-only calls share their public turn but not their call ID", context do
    turn = make_ref()
    state = call(context.state, context.capability, make_ref(), turn)
    assert_receive {:vxpipe_event, %ToolCallStarted{} = first}
    _state = call(state, context.capability, make_ref(), turn)
    assert_receive {:vxpipe_event, %ToolCallStarted{} = second}
    assert second.correlation_id == first.correlation_id
    assert second.command_id == first.command_id
    refute second.tool_call_id == first.tool_call_id
  end

  test "a binary spelling of a private reference cannot acquire its public audio turn", context do
    turn = make_ref()
    state = SpeechToSpeech.handle_turn_started(context.state, context.capability, @agent, turn)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{} = speech}
    _state = call(state, context.capability, make_ref(), inspect(turn))
    assert_receive {:vxpipe_event, %ToolCallStarted{} = tool}
    refute tool.correlation_id == speech.correlation_id
    refute tool.command_id == speech.command_id
  end

  test "new tools cannot acquire audio-turn IDs from a replaced source", context do
    turn = make_ref()
    state = SpeechToSpeech.handle_turn_started(context.state, context.capability, @agent, turn)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{} = speech}
    state = invalidate(state, :rebound_source, context.capability)
    state = call(state, context.capability, make_ref(), turn)
    [pending] = Map.values(state.sts_tool_calls)
    refute pending.turn.correlation_id == speech.correlation_id
  end

  test "held or closed input cannot admit tool work", context do
    closed = %{
      context.state
      | speech_to_speech_capability: %{
          context.state.speech_to_speech_capability
          | input_epoch: nil
        }
    }

    held = %{context.state | held_participant_ids: MapSet.new(["human"])}

    for state <- [closed, held] do
      assert call(state, context.capability, make_ref(), make_ref()) == state
    end

    refute_received {:vxpipe_event, _}
    refute_received {:provider_tool_result, _, _}
  end

  test "an allowlisted tool cannot be attributed to another agent", context do
    call = make_ref()

    assert SpeechToSpeech.handle_tool_call(
             context.state,
             context.capability,
             "other-agent",
             call,
             make_ref(),
             "echo",
             %{}
           ) == context.state

    refute_received {:vxpipe_event, _}
    refute_received {:provider_tool_result, _, _}
  end

  test "unknown and wrong-agent cancellations cannot fabricate or settle events", context do
    assert SpeechToSpeech.handle_tool_cancelled(
             context.state,
             context.capability,
             @agent,
             make_ref()
           ) == context.state

    refute_received {:vxpipe_event, _}
    call = make_ref()
    state = call(context.state, context.capability, call, make_ref())
    assert_receive {:vxpipe_event, %ToolCallStarted{}}

    assert SpeechToSpeech.handle_tool_cancelled(state, context.capability, "other-agent", call) ==
             state

    refute_received {:vxpipe_event, _}
  end

  for mutation <- [
        :missing_source,
        :replaced_owner,
        :rebound_source,
        :retired_epoch,
        :held_source
      ] do
    test "#{mutation} retires completion without sending it to the provider", context do
      call = make_ref()
      state = call(context.state, context.capability, call, make_ref())
      assert_receive {:vxpipe_event, %ToolCallStarted{}}
      state = invalidate(state, unquote(mutation), context.capability)

      state =
        SpeechToSpeech.deliver_tool_result(state, context.capability, call, %{
          "private" => "result"
        })

      assert state.sts_tool_calls == %{}
      refute_received {:provider_tool_result, _, _}
      refute_received {:vxpipe_event, _}
    end
  end

  test "source loss still retires cancellation without a fabricated publication", context do
    call = make_ref()
    state = call(context.state, context.capability, call, make_ref())
    assert_receive {:vxpipe_event, %ToolCallStarted{}}

    state =
      SpeechToSpeech.handle_tool_cancelled(
        %{state | connections: %{}},
        context.capability,
        @agent,
        call
      )

    assert state.sts_tool_calls == %{}
    refute_received {:vxpipe_event, _}
  end

  test "capability replacement drops old tool associations", context do
    call = make_ref()
    state = call(context.state, context.capability, call, make_ref())
    assert_receive {:vxpipe_event, %ToolCallStarted{}}
    state = SpeechToSpeech.bind_capability(state, self(), @agent)
    assert state.sts_tool_calls == %{}
    assert SpeechToSpeech.deliver_tool_result(state, context.capability, call, %{}) == state
    refute_received {:provider_tool_result, _, _}
  end

  test "pending room associations reject the seventeenth call without evicting accepted work",
       context do
    state =
      Enum.reduce(1..16, context.state, fn _, state ->
        state = call(state, context.capability, make_ref(), make_ref())
        assert_receive {:vxpipe_event, %ToolCallStarted{}}
        state
      end)

    call = make_ref()
    turn = make_ref()
    next = call(state, context.capability, call, turn)
    assert next.sts_tool_calls == state.sts_tool_calls
    assert_receive {:vxpipe_event, %ToolCallFailed{reason: :busy} = failed}
    assert_public_ids(failed, call, turn)
    assert_receive {:provider_tool_result, ^call, %{"error" => "tool_failed"}}
    refute_received {:vxpipe_event, %ToolCallStarted{}}
  end

  test "unauthorized calls use safe public failure identities", context do
    call = make_ref()
    turn = "private-denied-turn"

    _state =
      SpeechToSpeech.handle_tool_call(
        context.state,
        context.capability,
        @agent,
        call,
        turn,
        "denied",
        %{}
      )

    assert_receive {:vxpipe_event, %ToolCallFailed{reason: :unauthorized} = failed}
    assert_public_ids(failed, call, turn)
  end

  for reason <- [:timeout, :invalid_result] do
    test "#{reason} preserves the started public IDs and settles only once", context do
      call = make_ref()
      state = call(context.state, context.capability, call, make_ref())
      assert_receive {:vxpipe_event, %ToolCallStarted{} = started}

      state =
        case unquote(reason) do
          :timeout ->
            SpeechToSpeech.handle_tool_timeout(state, context.capability, call)

          :invalid_result ->
            SpeechToSpeech.deliver_tool_result(state, context.capability, call, "not an object")
        end

      assert_receive {:vxpipe_event, %ToolCallFailed{reason: reason} = failed}
      assert reason == unquote(reason)
      assert ids(failed) == ids(started)
      assert_receive {:provider_tool_result, ^call, %{"error" => "tool_failed"}}
      assert state.sts_tool_calls == %{}
      assert SpeechToSpeech.handle_tool_timeout(state, context.capability, call) == state
      assert SpeechToSpeech.deliver_tool_result(state, context.capability, call, %{}) == state
      refute_received {:provider_tool_result, _, _}
      refute_received {:vxpipe_event, _}
    end
  end

  defp call(state, capability, call, turn),
    do: SpeechToSpeech.handle_tool_call(state, capability, @agent, call, turn, "echo", %{})

  defp ids(event),
    do: {event.tool_call_id, event.command_id, event.correlation_id, event.connection_id}

  defp assert_public_ids(event, call, turn) do
    assert event.tool_call_id != inspect(call)
    assert String.starts_with?(event.tool_call_id, "tlatt_")
    assert String.starts_with?(event.command_id, "cmd_")
    assert String.starts_with?(event.correlation_id, "turn_")
    refute event.correlation_id in [turn, inspect(turn)]
    assert event.participant_id == @agent
    assert event.connection_id == @source
  end

  defp invalidate(state, :missing_source, _capability), do: %{state | connections: %{}}

  defp invalidate(state, :held_source, _capability),
    do: %{state | held_participant_ids: MapSet.new(["human"])}

  defp invalidate(state, :replaced_owner, capability) do
    source = Map.fetch!(state.connections, @source)
    %{state | connections: %{@source => %{source | pid: capability}}}
  end

  defp invalidate(state, :rebound_source, capability) do
    state = invalidate(state, :replaced_owner, capability)
    source = Map.fetch!(state.connections, @source)

    binding = %{
      state.speech_to_speech_capability
      | connection: capability,
        input_handle: STSInputHandle.new(source.attach_command, capability)
    }

    %{state | speech_to_speech_capability: binding}
  end

  defp invalidate(state, :retired_epoch, _capability) do
    %{
      state
      | speech_to_speech_capability: %{
          state.speech_to_speech_capability
          | input_epoch: make_ref()
        }
    }
  end

  defp state(capability) do
    snapshot = %Snapshot{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      lifecycle: :open,
      created_by_actor_id: "actor",
      created_by_command_id: "command"
    }

    {:ok, command} =
      AttachConnection.new(
        tenant_id: snapshot.tenant_id,
        room_id: snapshot.room_id,
        incarnation_id: snapshot.incarnation_id,
        actor_id: "actor",
        participant_id: "human",
        connection_id: @source,
        deadline: DateTime.add(DateTime.utc_now(), 5, :second)
      )

    source = %{
      pid: self(),
      participant_id: "human",
      role: :human,
      admission: :main,
      attach_command: command
    }

    state = State.new(%Recorder{port: nil, participant_activations: %{}}, snapshot, %{})

    state =
      SpeechToSpeech.bind_capability(
        %{state | connections: %{@source => source}},
        capability,
        @agent
      )

    binding =
      Map.merge(state.speech_to_speech_capability, %{
        connection_id: @source,
        connection: self(),
        input_epoch: make_ref(),
        input_handle: STSInputHandle.new(command, self())
      })

    tool = %{name: "echo", type: :mcp, conversation_mode: :non_blocking}

    participants =
      Map.new([@agent, "other-agent"], fn id ->
        {id, %{kind: :agent, participant_id: id, tools: %{"echo" => tool}}}
      end)

    %{
      state
      | speech_to_speech_capability: binding,
        participant_transfer_runtime: %{plan: %{participants: participants}}
    }
  end
end
