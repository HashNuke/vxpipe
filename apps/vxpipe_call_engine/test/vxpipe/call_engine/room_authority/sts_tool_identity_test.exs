defmodule Vxpipe.CallEngine.RoomAuthority.STSToolIdentityTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.AgentRuntime.ToolRegistry
  alias Vxpipe.CallEngine.AgentRuntime.ToolDescriptors
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    ToolCallStarted,
    ToolCallCompleted,
    ToolCallCancelled,
    ToolCallFailed
  }

  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{SpeechToSpeech, State}
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.{ToolEvents, Tools}
  alias Vxpipe.CallEngine.STSInputHandle
  alias Vxpipe.CallEngine.SpeechToSpeechRuntime
  alias Vxpipe.CallEngine.Tool.{InvocationRegistry, InvocationSupervisor}

  @agent "agent"
  @source "source"
  @activation "activation"

  setup do
    capability = start_supervised!({Vxpipe.CallEngine.STSToolResultReceiver, self()})
    {:ok, _} = Registry.register(Vxpipe.CallEngine.RoomRegistry, {Tree, :parent, capability}, nil)

    supervisor =
      start_supervised!({InvocationSupervisor, activation_id: @activation, maximum_children: 16})

    start_supervised!(
      {InvocationRegistry,
       name:
         {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {Tree, self(), :invocation_registry}}},
       activation_id: @activation,
       invocation_supervisor: supervisor,
       completion_target: self(),
       maximum_invocations: 16,
       maximum_consumed_invocations: 16,
       invocation_timeout_ms: 5_000,
       maximum_result_bytes: 65_536}
    )

    authority = start_supervised!({Vxpipe.CallEngine.TestSTSPolicySnapshot, policy()})
    %{capability: capability, state: %{state(capability) | media_policy_authority: authority}}
  end

  for kind <- [:binary, :reference] do
    test "#{kind} tool-only references stay private through completion", context do
      turn = if unquote(kind) == :binary, do: "private-provider-turn", else: make_ref()
      call = make_ref()
      state = call(context.state, context.capability, call, turn)
      assert_receive {:vxpipe_event, %ToolCallStarted{} = started}
      assert_public_ids(started, call, turn)

      state = complete_tool(state, context.capability, call, %{"ok" => true})
      assert_receive {:vxpipe_event, %ToolCallCompleted{} = completed}
      assert ids(completed) == ids(started)
      assert_receive {:provider_tool_result, ^call, %{"ok" => true}}
      assert state.sts_tool_calls == %{}
      assert complete_tool(state, context.capability, call, %{}) == state
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
             "echo_context",
             %{}
           ) == context.state

    refute_received {:vxpipe_event, _}
    refute_received {:provider_tool_result, _, _}
  end

  @tag :registry_scope
  test "a private registry cannot authorize work from a different capability activation",
       context do
    state = %{
      context.state
      | speech_to_speech_capability: %{
          context.state.speech_to_speech_capability
          | activation_id: "retired-activation"
        }
    }

    state = call(state, context.capability, make_ref(), make_ref())
    assert_receive {:vxpipe_event, %ToolCallFailed{reason: :unauthorized}}
    refute_received {:vxpipe_event, %ToolCallStarted{}}
    assert state.sts_tool_calls == %{}
    assert {:ok, []} = InvocationRegistry.snapshot(Tree.invocation_registry(context.capability))
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
        complete_tool(state, context.capability, call, %{
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
    assert complete_tool(state, context.capability, call, %{}) == state
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

  for reason <- [:unknown, :invalid_result] do
    test "#{reason} preserves the started public IDs and settles only once", context do
      call = make_ref()
      state = call(context.state, context.capability, call, make_ref())
      assert_receive {:vxpipe_event, %ToolCallStarted{} = started}

      state =
        case unquote(reason) do
          :unknown ->
            expire_tool(state, context.capability, call)

          :invalid_result ->
            complete_tool(state, context.capability, call, "not an object")
        end

      assert_receive {:vxpipe_event, %ToolCallFailed{reason: reason} = failed}
      assert reason == unquote(reason)
      assert ids(failed) == ids(started)

      expected_result =
        if unquote(reason) == :unknown,
          do: %{"status" => "unknown"},
          else: %{"error" => "tool_failed"}

      assert_receive {:provider_tool_result, ^call, ^expected_result}
      assert state.sts_tool_calls == %{}
      assert expire_tool(state, context.capability, call) == state
      assert complete_tool(state, context.capability, call, %{}) == state
      refute_received {:provider_tool_result, _, _}
      refute_received {:vxpipe_event, _}
    end
  end

  test "replayed owner envelopes cannot reopen settled work", context do
    call = make_ref()
    evidence = tool_evidence(context.state, call, 10)
    state = tool_event(context.state, context.capability, evidence)
    assert_receive {:vxpipe_event, %ToolCallStarted{} = started}
    state = complete_tool(state, context.capability, call, %{})
    assert_receive {:vxpipe_event, %ToolCallCompleted{} = completed}
    assert_receive {:provider_tool_result, ^call, %{}}
    assert ids(completed) == ids(started)
    assert tool_event(state, context.capability, evidence) == state
    assert state.sts_tool_sequence == 10
    refute_received {:vxpipe_event, _}
  end

  test "wrong agent, source, epoch and policy cannot admit an ordered tool event", context do
    evidence = tool_evidence(context.state, make_ref(), 1)

    assert ToolEvents.handle(context.state, context.capability, "other-agent", evidence, policy()) ==
             context.state

    assert tool_event(context.state, self(), evidence) == context.state

    for invalid <- [
          %{evidence | epoch: make_ref()},
          %{evidence | identity: %{evidence.identity | connection_id: "other"}},
          %{evidence | audio_interval: 1}
        ] do
      assert tool_event(context.state, context.capability, invalid) == context.state
    end

    denied = %{policy() | effective: %{policy().effective | audio_routes: %{}}}

    assert ToolEvents.handle(context.state, context.capability, @agent, evidence, denied) ==
             context.state

    refute_received {:vxpipe_event, _}
  end

  test "cancellation retires only its original scope, including after an epoch change", context do
    call = make_ref()
    evidence = tool_evidence(context.state, call, 1)
    state = tool_event(context.state, context.capability, evidence)
    assert_receive {:vxpipe_event, %ToolCallStarted{}}
    cancel = %{evidence | event: %{evidence.event | kind: :tool_cancelled, sequence: 2}}
    wrong = %{cancel | epoch: make_ref()}
    assert tool_event(state, context.capability, wrong).sts_tool_calls == state.sts_tool_calls
    state = invalidate(state, :retired_epoch, context.capability)
    state = tool_event(state, context.capability, cancel)
    assert state.sts_tool_calls == %{}
    assert state.sts_tool_sequence == 2
    assert tool_event(state, context.capability, evidence) == state
    refute_received {:vxpipe_event, _}
    refute_received {:provider_tool_result, _, _}
  end

  test "legacy unqualified owner messages are ignored", context do
    alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Events

    assert {:noreply, state} =
             Events.handle(
               {:vxpipe_sts_tool_call, context.capability, @agent, make_ref(), make_ref(),
                "echo_context", %{}},
               context.state
             )

    assert state == context.state
    refute_received {:vxpipe_event, _}
  end

  test "room hold retires provider associations even without a provider cancellation", context do
    call = make_ref()
    state = tool_event(context.state, context.capability, tool_evidence(context.state, call, 1))
    assert_receive {:vxpipe_event, %ToolCallStarted{}}
    state = SpeechToSpeech.hold(state)
    assert_receive :sts_receiver_held
    assert state.sts_tool_calls == %{}
    assert state.speech_to_speech_capability.input_epoch == nil
    assert state.sts_tool_sequence == 1
    assert_receive {:vxpipe_event, %ToolCallCancelled{}}
    assert complete_tool(state, context.capability, call, %{}) == state
    refute_received {:provider_tool_result, _, _}
  end

  for change <- [:denied, :regranted, :absent, :unavailable] do
    test "#{change} policy prevents delivery of an admitted tool result", context do
      call = make_ref()
      evidence = tool_evidence(context.state, call, 1)
      state = tool_event(context.state, context.capability, evidence)
      assert_receive {:vxpipe_event, %ToolCallStarted{}}

      changed =
        case unquote(change) do
          :denied -> %{policy() | effective: %{policy().effective | audio_routes: %{}}}
          :regranted -> %{policy() | revision: 2}
          :absent -> %{policy() | present_participant_ids: MapSet.new([@agent])}
          :unavailable -> nil
        end

      :ok = GenServer.call(state.media_policy_authority, {:replace, changed})
      state = complete_tool(state, context.capability, call, %{})
      assert state.sts_tool_calls == %{}
      refute_received {:provider_tool_result, _, _}
      refute_received {:vxpipe_event, _}
    end
  end

  test "completed tool history retains only a sequence watermark", context do
    state =
      Enum.reduce(1..50, context.state, fn sequence, state ->
        call = make_ref()
        state = tool_event(state, context.capability, tool_evidence(state, call, sequence))
        assert_receive {:vxpipe_event, %ToolCallStarted{}}
        state = complete_tool(state, context.capability, call, %{})
        assert_receive {:vxpipe_event, %ToolCallCompleted{}}
        assert_receive {:provider_tool_result, ^call, %{}}
        assert state.sts_tool_calls == %{}
        assert state.sts_tool_sequence == sequence
        state
      end)

    replacement = SpeechToSpeech.bind_capability(state, self(), @agent)
    assert replacement.sts_tool_sequence == 0
    assert replacement.sts_tool_calls == %{}
  end

  @tag :shared_effects
  test "an admitted hangup publishes only its public result before the room effect", context do
    {state, effect} = settle_hangup(context)

    assert {:stop, {:shutdown, :agent_hangup}, ^state} =
             Vxpipe.CallEngine.RoomAuthority.handle_info(effect, state)
  end

  for change <- [:rebound_source, :retired_epoch, :held_source, :denied_policy, :regranted_policy] do
    @tag :shared_effects
    test "#{change} fences a queued hangup effect", context do
      {state, effect} = settle_hangup(context)

      state = invalidate_effect(state, unquote(change), context.capability)

      assert {:noreply, ^state} = Vxpipe.CallEngine.RoomAuthority.handle_info(effect, state)
    end
  end

  defp invalidate_effect(state, :denied_policy, _capability) do
    denied = %{policy() | effective: %{policy().effective | audio_routes: %{}}}
    :ok = GenServer.call(state.media_policy_authority, {:replace, denied})
    state
  end

  defp invalidate_effect(state, :regranted_policy, _capability) do
    :ok = GenServer.call(state.media_policy_authority, {:replace, %{policy() | revision: 2}})
    state
  end

  defp invalidate_effect(state, change, capability), do: invalidate(state, change, capability)

  defp settle_hangup(context) do
    call = make_ref()
    evidence = tool_evidence(context.state, call, 1)
    evidence = %{evidence | event: %{evidence.event | tool_name: "end_call"}}
    state = tool_event(context.state, context.capability, evidence)
    assert_receive {:vxpipe_event, %ToolCallStarted{name: "end_call"}}

    outcome =
      {:ok,
       %Vxpipe.CallEngine.Tool.PlatformResult{effect: :hangup, result: %{"status" => "ending"}}}

    state = Tools.handle_tool_executed(state, context.capability, call, outcome)
    assert_receive {:provider_tool_result, ^call, %{"status" => "ending"}}
    assert_receive {:vxpipe_event, %ToolCallCompleted{result: %{"status" => "ending"}}}
    assert_receive {:vxpipe_sts_platform_effect, _, _, :hangup} = effect
    assert state.sts_tool_calls == %{}
    {state, effect}
  end

  defp complete_tool(state, capability, call, result),
    do: Tools.handle_tool_executed(state, capability, call, {:ok, result})

  defp expire_tool(state, capability, call),
    do: Tools.handle_tool_executed(state, capability, call, {:error, :unknown})

  defp tool_event(state, capability, evidence) do
    next = ToolEvents.handle(state, capability, @agent, evidence, policy())
    drain_invocations(state, next, capability)
  end

  defp tool_evidence(state, call, sequence) do
    %{
      identity: state.speech_to_speech_capability.input_handle.identity,
      epoch: state.speech_to_speech_capability.input_epoch,
      audio_interval: 0,
      event: %Vxpipe.CallEngine.Speech.Event{
        kind: :tool_call,
        call_ref: call,
        turn_ref: make_ref(),
        sequence: sequence,
        tool_name: "echo_context",
        arguments: %{}
      }
    }
  end

  defp policy do
    %Vxpipe.CallEngine.MediaPolicy.Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["human", @agent]),
      effective: %Vxpipe.CallEngine.MediaPolicy.Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: false,
        save_transcripts: false
      }
    }
  end

  defp call(state, capability, call, turn) do
    next =
      SpeechToSpeech.handle_tool_call(state, capability, @agent, call, turn, "echo_context", %{})

    drain_invocations(state, next, capability)
  end

  # These tests control room publication separately from execution. Consume the
  # actual worker's result so identity tests do not depend on retained capacity.
  defp drain_invocations(previous, next, capability) do
    registry = Tree.invocation_registry(capability)

    for {call, pending} <- next.sts_tool_calls,
        not Map.has_key?(previous.sts_tool_calls, call) do
      id = pending.tool_call_id
      assert_receive {:vxpipe_tool_completion_available, ^registry, ^id}, 1_000
      assert {:ok, lease} = InvocationRegistry.lease_next(registry, "identity-test")
      assert lease.invocation_id == id
      assert :ok = InvocationRegistry.acknowledge_completion(registry, id, lease.lease_id)
    end

    next
  end

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

    state =
      State.new(
        %Recorder{port: nil, participant_activations: %{@agent => @activation}},
        snapshot,
        %{}
      )

    state =
      SpeechToSpeech.bind_capability(
        %{state | connections: %{@source => source}},
        capability,
        @agent,
        @activation
      )

    binding =
      Map.merge(state.speech_to_speech_capability, %{
        connection_id: @source,
        connection: self(),
        input_epoch: make_ref(),
        input_handle: STSInputHandle.new(command, self())
      })

    tool = %ToolBinding{
      name: "echo_context",
      type: :host,
      action: Vxpipe.CallEngine.STSContextTool,
      conversation_mode: :blocking
    }

    hangup = %ToolBinding{
      name: "end_call",
      type: :platform,
      action: Vxpipe.CallEngine.Tool.Hangup,
      conversation_mode: :blocking
    }

    {:ok, descriptors} = ToolDescriptors.compile(%{"echo_context" => tool, "end_call" => hangup})
    {:ok, registry} = ToolRegistry.new(descriptors)

    runtime = %SpeechToSpeechRuntime{
      provider: {Vxpipe.Providers.MorseCode.STSSession, []},
      provider_private: [],
      call_id: snapshot.room_id,
      participant_id: @agent,
      activation_id: @activation,
      usage_provider: nil,
      tool_registry: registry
    }

    %{
      state
      | speech_to_speech_capability: binding,
        speech_to_speech_runtime: runtime
    }
  end
end
