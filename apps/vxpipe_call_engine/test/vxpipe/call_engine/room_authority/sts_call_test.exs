defmodule Vxpipe.CallEngine.RoomAuthority.STSCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestCallStartup, TestTransferConnection}
  alias Vxpipe.Providers.MorseCode.STSSession
  alias Vxpipe.CallEngine.Media.{AudioFrame, STSIngress}
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, ParticipantTranscription, TextOutput}
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder, Encoder}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :speech_to_speech, providers: %{STSSession => [enabled: true]})
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "a room without human STT accepts caller PCM and publishes its reply only after playback" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)
    command = attach_command(plan, room, caller)
    track = %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}
    assert {:ok, attachment} = TestTransferConnection.attach(command, sink, input_track: track)
    assert Map.has_key?(attachment, :speech_to_speech_input)
    assert attachment.media_ingress == nil
    room_id = plan.room_id
    assert_receive {:test_call_ready, ^room_id}, 2_000

    assert {:ok, %{ingress: ingress, format: format}} =
             Vxpipe.CallEngine.speech_to_speech_input_configuration(attachment)

    assert format == Map.delete(track, :track_id)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    {:ok, config} = Config.new([])
    {:ok, pcm} = Encoder.encode(config, "HI")

    for {chunk, sequence} <- Enum.with_index(for <<chunk::binary-size(320) <- pcm>>, do: chunk) do
      frame = audio_frame(command, chunk, sequence)

      assert :ok =
               TestTransferConnection.run(command, fn ->
                 Vxpipe.CallEngine.push_speech_to_speech_audio(attachment, frame)
               end)

      _ = :sys.get_state(capability)
      assert %{queued: 0, in_flight?: false, dropped: 0} = STSIngress.stats(ingress)
    end

    caller_id = caller.participant_id
    agent_id = agent.participant_id

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{text: "HI", final: true, participant_id: ^caller_id}},
                   1_000

    output = collect_output(sink, [])
    {:ok, decoder} = Decoder.new(config)
    assert {:ok, _, decoded} = Decoder.push(decoder, output)
    assert {:final, "RECEIVED HI"} in decoded
    refute_received {:vxpipe_event, %TextOutput{}}
    played_ms = div(byte_size(output) * 1_000, 16_000 * 2)
    :ok = TestAudioOutputSink.playback_progress(sink, played_ms, played_ms)
    :ok = TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      text: "RECEIVED HI",
                      participant_id: ^agent_id,
                      will_be_spoken: true
                    }},
                   1_000

    assert_receive {:vxpipe_event, %AgentTurnCompleted{participant_id: ^agent_id}}, 1_000
    refute_received {:vxpipe_event, %TextOutput{}}
  end

  test "the receiver rechecks framed input and rejects stale hold epochs and raw audio" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)
    command = attach_command(plan, room, caller)
    track = %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}
    assert {:ok, attachment} = TestTransferConnection.attach(command, sink, input_track: track)
    room_id = plan.room_id
    assert_receive {:test_call_ready, ^room_id}, 2_000

    {:ok, %{ingress: ingress}} =
      Vxpipe.CallEngine.speech_to_speech_input_configuration(attachment)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    state = :sys.get_state(capability)
    frame = audio_frame(command, <<0, 0>>, 1)

    assert {:error, :wrong_connection} =
             Vxpipe.CallEngine.push_speech_to_speech_audio(attachment, frame)

    assert {:error, :framed_input_required} =
             Vxpipe.CallEngine.Capability.SpeechToSpeech.push_audio(
               capability,
               caller.participant_id,
               frame.payload
             )

    for invalid <- [
          %{frame | track_id: "other"},
          %{frame | sample_rate: 24_000},
          %{frame | payload: <<1>>},
          %{frame | participant_id: "foreign"},
          %{frame | received_at: frame.received_at - 1_000}
        ] do
      before = :sys.get_state(capability).dropped_ingress_chunks

      send(
        capability,
        {:vxpipe_sts_input, ingress, make_ref(), invalid, state.policy_revision,
         state.input_epoch}
      )

      assert :sys.get_state(capability).dropped_ingress_chunks == before + 1
    end

    assert :ok = Vxpipe.CallEngine.Capability.SpeechToSpeech.hold(capability)
    assert :ok = Vxpipe.CallEngine.Capability.SpeechToSpeech.release(capability)
    before = :sys.get_state(capability).dropped_ingress_chunks

    send(
      capability,
      {:vxpipe_sts_input, ingress, make_ref(), audio_frame(command, <<0, 0>>, 2),
       state.policy_revision, state.input_epoch}
    )

    assert :sys.get_state(capability).dropped_ingress_chunks == before + 1
  end

  test "a real STS room becomes ready and retires the allocation when its source disconnects" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "sts-connection-#{System.unique_integer([:positive])}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, attachment} =
             TestTransferConnection.attach(command, sink,
               input_track: %{
                 track_id: "microphone",
                 codec: :linear16,
                 sample_rate: 16_000,
                 channels: 1
               }
             )

    room_id = plan.room_id

    receive do
      {:test_call_ready, ^room_id} -> :ok
    after
      2_000 ->
        [{authority, _}] =
          Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})

        state = :sys.get_state(authority)

        flunk(
          "STS readiness failed: #{inspect(Map.take(state, [:startup, :speech_to_speech_ready?]))}"
        )
    end

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    assert is_pid(capability)

    assert {:ok, %{ingress: ingress}} =
             Vxpipe.CallEngine.speech_to_speech_input_configuration(attachment)

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})

    policy_authority = Vxpipe.CallEngine.MediaPolicy.Authority.whereis(room.incarnation_id)
    policy = Vxpipe.CallEngine.MediaPolicy.Authority.snapshot(policy_authority)

    assert {:ok, candidate} =
             Vxpipe.CallEngine.MediaPolicy.Authority.preview_presence(
               policy_authority,
               policy.present_participant_ids
             )

    assert {:ok, graph} = Vxpipe.CallEngine.Readiness.Preparation.run(authority, candidate)

    assert Enum.any?(graph.resources, fn resource ->
             resource.kind == :speech_to_speech and resource.instance == capability and
               resource.scope == {:participant, agent.participant_id}
           end)

    assert Enum.any?(graph.resources, fn resource ->
             resource.kind == :speech_to_speech_ingress and resource.instance == ingress and
               resource.scope == {:participant, caller.participant_id} and
               resource.binding == command.connection_id
           end)

    tree = Tree.parent(capability)
    assert is_pid(tree)
    capability_monitor = Process.monitor(capability)
    tree_monitor = Process.monitor(tree)
    ingress_monitor = Process.monitor(ingress)

    duplicate = %{command | connection_id: command.connection_id <> "-duplicate"}

    assert {:error, %Vxpipe.CallEngine.Error{code: :sts_source_already_attached}} =
             TestTransferConnection.attach(duplicate, sink)

    stop_supervised!({TestTransferConnection, command.connection_id})
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _}, 1_000
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _}, 1_000
    assert_receive {:DOWN, ^ingress_monitor, :process, ^ingress, _}, 1_000
  end

  test "rejected policy registration retires the candidate instead of binding it" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    state = :sys.get_state(authority)
    snapshot = Vxpipe.CallEngine.MediaPolicy.Authority.snapshot(state.media_policy_authority)

    rejecting =
      start_supervised!(
        {Vxpipe.CallEngine.TestSTSRejectingPolicyAuthority, snapshot: snapshot, observer: self()}
      )

    state = %{state | media_policy_authority: rejecting}

    connection = %{
      output_sink: sink,
      pid: self(),
      participant_id: caller.participant_id,
      role: :human,
      admission: :main,
      attach_command: attach_command(plan, room, caller)
    }

    state = %{state | connections: %{connection.attach_command.connection_id => connection}}
    result = Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.maybe_start(state, connection)
    capability = result.speech_to_speech_capability.pid

    assert {:error, :held} =
             Vxpipe.CallEngine.Capability.SpeechToSpeech.push_audio(
               capability,
               caller.participant_id,
               <<0, 0>>
             )

    assert_receive {:vxpipe_sts_ready, ^capability}
    result = Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.handle_ready(result, capability)
    assert result.speech_to_speech_capability == nil
    assert_receive {:sts_policy_registration_rejected, capability, tree}
    capability_monitor = Process.monitor(capability)
    tree_monitor = Process.monitor(tree)
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _}
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _}

    assert RoomCapabilitySupervisor.whereis_speech_to_speech(
             room.incarnation_id,
             state.speech_to_speech_runtime.participant_id
           ) == nil
  end

  test "a monitor or foreign source never starts the caller's STS allocation" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    state = :sys.get_state(authority)
    command = attach_command(plan, room, caller)

    connection = %{
      pid: self(),
      output_sink: sink,
      participant_id: caller.participant_id,
      role: :monitor,
      admission: :main,
      attach_command: command
    }

    state = %{state | connections: %{command.connection_id => connection}}
    assert Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.maybe_start(state, connection) == state
    foreign = %{connection | role: :human, participant_id: "foreign"}
    state = %{state | connections: %{command.connection_id => foreign}}
    assert Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.maybe_start(state, foreign) == state
  end

  test "the pinned plan rejects duplicate source admission while startup is still preparing" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, _room} = TestCallStartup.start_call(plan)

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    state = :sys.get_state(authority)

    state = %{
      state
      | speech_to_speech_runtime: nil,
        connections: %{
          "early" => %{role: :human, admission: :main, participant_id: caller.participant_id}
        }
    }

    assert {:error, %Vxpipe.CallEngine.Error{code: :sts_source_already_attached}} =
             Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.authorize_connection(
               state,
               caller.participant_id
             )
  end

  test "installing entry preparation binds an already attached caller" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    state = :sys.get_state(authority)
    command = attach_command(plan, room, caller)

    connection = %{
      pid: self(),
      output_sink: sink,
      participant_id: caller.participant_id,
      role: :human,
      admission: :main,
      attach_command: command
    }

    prepared = %{
      participant: nil,
      voice: nil,
      configuration: %{
        speech_to_text_runtimes: %{},
        text_to_speech: nil,
        speech_to_speech: state.speech_to_speech_runtime,
        agent_activation: nil,
        receiver: %{kind: :agent}
      }
    }

    early = %{
      state
      | speech_to_speech_runtime: nil,
        connections: %{command.connection_id => connection}
    }

    assert {:ok, installed} = Vxpipe.CallEngine.RoomAuthority.Startup.install(prepared, early)

    assert %{pid: capability, connection_id: connection_id} =
             installed.speech_to_speech_capability

    assert connection_id == command.connection_id
    assert_receive {:vxpipe_sts_ready, ^capability}
    installed = Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.handle_ready(installed, capability)
    assert installed.speech_to_speech_ready?

    assert Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.stop(installed).speech_to_speech_capability ==
             nil
  end

  defp collect_output(sink, frames) do
    receive do
      {:test_audio_output, ^sink, frame} ->
        collect_output(sink, [frame.payload | frames])

      {:test_audio_output_finish, ^sink, _turn} ->
        frames |> Enum.reverse() |> IO.iodata_to_binary()
    after
      2_000 -> flunk("STS reply did not reach the room output sink")
    end
  end

  defp audio_frame(command, payload, sequence) do
    %AudioFrame{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      participant_id: command.participant_id,
      connection_id: command.connection_id,
      track_id: "microphone",
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: sequence,
      timestamp: sequence * 160,
      payload: payload,
      received_at: System.monotonic_time(:millisecond)
    }
  end

  defp attach_command(plan, room, caller) do
    {:ok, command} =
      AttachConnection.new(
        tenant_id: plan.tenant_id,
        actor_id: plan.actor_id,
        room_id: plan.room_id,
        incarnation_id: room.incarnation_id,
        participant_id: caller.participant_id,
        connection_id: "sts-connection-#{System.unique_integer([:positive])}",
        deadline: DateTime.add(DateTime.utc_now(), 5, :second)
      )

    command
  end

  defp compile_plan do
    source = %{
      schema_version: "20260915.01",
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Reply using Morse speech.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: [],
          capabilities: %{speech_to_speech: %{provider: "morse", model: "morse", options: %{}}}
        }
      }
    }

    assert {:ok, spec} = CallSpec.new(source, resource_id: "sts-room", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "sts-room", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-sts-room",
               actor_id: "actor-sts-room"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end
end
