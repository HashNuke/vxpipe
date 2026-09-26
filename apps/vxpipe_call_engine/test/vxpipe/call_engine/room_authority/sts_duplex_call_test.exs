defmodule Vxpipe.CallEngine.RoomAuthority.STSDuplexCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    AgentTurnCompleted,
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput,
    ToolCallCompleted,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Media.{AudioFrame, STSIngress}
  alias Vxpipe.CallEngine.MediaPolicy.Authority, as: MediaPolicyAuthority
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder, Encoder}
  alias Vxpipe.CallEngine.Speech.Session
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestCallStartup, TestTransferConnection}
  alias Vxpipe.Providers.MorseCode.DuplexSTSSession

  @morse [unit_duration_ms: 60]
  @track %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    settings =
      Keyword.put(original, :speech_to_speech, providers: %{DuplexSTSSession => [enabled: true]})

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
  end

  test "one caller utterance and its spoken reply settle as one turn each" do
    context = room()
    push_sts(context, context.pcm)
    caller = context.caller

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{participant_id: ^caller} = started},
                   5_000

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{participant_id: ^caller, text: "HI", final: true}},
                   5_000

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{participant_id: ^caller} = completed},
                   5_000

    assert completed.correlation_id == started.correlation_id
    assert completed.endpointing == :inferred_gap
    assert_receive {:vxpipe_event, %AgentSpeechStarted{} = agent_started}, 5_000
    output = collect_output(context.sink, [])
    assert {:ok, decoder} = Decoder.new(context.config)
    assert {:ok, _decoder, events} = Decoder.push(decoder, output)
    assert {:partial, "RECEIVED HI"} in events
    refute_received {:vxpipe_event, %TextOutput{}}
    played = div(byte_size(output) * 1_000, 16_000 * 2)
    assert :ok = TestAudioOutputSink.playback_progress(context.sink, played, played)
    assert :ok = TestAudioOutputSink.playback_completed(context.sink)

    assert_receive {:vxpipe_event,
                    %TextOutput{text: "RECEIVED HI", correlation_id: correlation_id}},
                   5_000

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^correlation_id}},
                   5_000

    assert correlation_id == agent_started.correlation_id
    refute_received {:vxpipe_event, %ParticipantTurnStarted{}}
    refute_received {:vxpipe_event, %AgentSpeechStarted{}}
  end

  test "caller speech over an active reply completes that agent turn as overlapped" do
    context = room()
    push_sts(context, context.pcm)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{} = started}, 5_000
    {first_end_ms, generated_ms} = await_first_word(context, 0)

    assert :ok =
             TestAudioOutputSink.playback_progress(context.sink, first_end_ms, generated_ms)

    assert {:ok, backchannel} = Encoder.encode(context.config, "I")
    sequence_offset = div(byte_size(context.pcm), 320)
    push_sts(context, backchannel, sequence_offset)
    _discarded_tail = collect_output(context.sink, [])
    assert :ok = TestAudioOutputSink.playback_completed(context.sink)

    assert_receive {:vxpipe_event,
                    %AgentTurnCompleted{correlation_id: correlation_id, outcome: :overlapped}},
                   5_000

    assert correlation_id == started.correlation_id
    assert_receive {:vxpipe_event, %TextOutput{text: "RECEIVED"}}, 5_000
    refute_received {:vxpipe_event, %TextOutput{text: "RECEIVED HI"}}
  end

  test "a short caller tone does not interrupt the active reply" do
    context = room()
    push_sts(context, context.pcm)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{} = started}, 5_000
    assert_receive {:test_audio_output, sink, first_frame}, 5_000
    assert sink == context.sink

    assert {:ok, tone} = Encoder.encode(context.config, "E")
    <<short_tone::binary-size(160), _::binary>> = tone
    push_sts(context, short_tone, div(byte_size(context.pcm), 320))

    rest = collect_output(sink, [])
    output = first_frame.payload <> rest
    played = div(byte_size(output) * 1_000, 16_000 * 2)
    assert :ok = TestAudioOutputSink.playback_progress(sink, played, played)
    assert :ok = TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_event,
                    %TextOutput{text: "RECEIVED HI", correlation_id: correlation_id}},
                   5_000

    assert correlation_id == started.correlation_id

    assert_receive {:vxpipe_event,
                    %AgentTurnCompleted{correlation_id: ^correlation_id, outcome: :completed}},
                   5_000
  end

  test "a room mute keeps a tool in flight and speaks its result after release" do
    tools = %{
      "echo_context" => %{
        type: "host",
        tool: "echo_context",
        conversation_mode: "non_blocking"
      }
    }

    context = room(tools)
    provider = context.provider

    assert :ok =
             CallEngine.Capability.SpeechToSpeech.push_text(
               context.capability,
               "TOOL echo_context {}"
             )

    assert_receive {:vxpipe_event, %ToolCallStarted{}}, 5_000
    state = :sys.get_state(context.authority)
    [{call_ref, _pending}] = Map.to_list(state.sts_tool_calls)

    held = :sys.replace_state(context.authority, &CallEngine.RoomAuthority.SpeechToSpeech.hold/1)
    assert Map.has_key?(held.sts_tool_calls, call_ref)
    assert held.speech_to_speech_capability.input_epoch == nil
    assert Session.provider(:sys.get_state(context.capability).session) == provider
    assert :sys.get_state(provider).held?
    assert :sys.get_state(provider).hold_log == [{:hold, :started}]
    refute :sys.get_state(context.ingress).open?

    settled =
      :sys.replace_state(context.authority, fn state ->
        CallEngine.RoomAuthority.SpeechToSpeech.deliver_tool_result(
          state,
          context.capability,
          call_ref,
          %{"text" => "OK"}
        )
      end)

    assert settled.sts_tool_calls == %{}
    assert_receive {:vxpipe_event, %ToolCallCompleted{}}, 5_000
    assert :sys.get_state(provider).held_tool_replies != []
    refute_received {:test_audio_output, _, _}

    released =
      :sys.replace_state(context.authority, &CallEngine.RoomAuthority.SpeechToSpeech.release/1)

    assert is_reference(released.speech_to_speech_capability.input_epoch)
    assert Session.provider(:sys.get_state(context.capability).session) == provider
    assert :sys.get_state(provider).hold_log == [{:hold, :started}, {:hold, :ended}]
    output = collect_output(context.sink, [])
    played = div(byte_size(output) * 1_000, 16_000 * 2)
    assert :ok = TestAudioOutputSink.playback_progress(context.sink, played, played)
    assert :ok = TestAudioOutputSink.playback_completed(context.sink)
    assert_receive {:vxpipe_event, %TextOutput{text: "RECEIVED TEXT OK"}}, 5_000
  end

  test "room policy denial publishes only the aligned word already played" do
    context = room(%{}, true)
    push_sts(context, context.pcm)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{}}, 5_000
    {first_end_ms, generated_ms} = await_first_word(context, 0)
    assert :ok = TestAudioOutputSink.playback_progress(context.sink, first_end_ms, generated_ms)

    state = :sys.get_state(context.authority)

    assert {:ok, _policy} =
             MediaPolicyAuthority.admit(state.media_policy_authority, context.privacy)

    assert_receive {:vxpipe_event, %TextOutput{text: "RECEIVED"}}, 5_000
    refute_received {:vxpipe_event, %TextOutput{text: "RECEIVED HI"}}
  end

  test "room policy denial before playback publishes no agent text" do
    context = room(%{}, true)
    push_sts(context, context.pcm)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{}}, 5_000
    state = :sys.get_state(context.authority)

    assert {:ok, _policy} =
             MediaPolicyAuthority.admit(state.media_policy_authority, context.privacy)

    _ = :sys.get_state(context.authority)
    refute_received {:vxpipe_event, %TextOutput{}}
  end

  test "room mute fences and discards a reply already in progress" do
    context = room()
    push_sts(context, context.pcm)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{}}, 5_000
    assert_receive {:test_audio_output, sink, _frame}, 5_000
    assert sink == context.sink

    held = :sys.replace_state(context.authority, &CallEngine.RoomAuthority.SpeechToSpeech.hold/1)
    assert held.speech_to_speech_capability.input_epoch == nil
    assert_receive {:test_audio_output_interrupt, ^sink, _turn, 0}, 5_000
    assert :sys.get_state(context.capability).active_output == nil

    case :sys.get_state(context.provider).timeline.output do
      nil -> :ok
      %{cursor: cursor, stream: stream} -> assert cursor == byte_size(stream)
    end

    refute_received {:vxpipe_event, %TextOutput{text: "RECEIVED HI"}}
  end

  test "a soft reply onset reaches the room sink before the louder activation frame" do
    context = room()
    push_sts(context, context.pcm)
    output = collect_output(context.sink, [])

    first_audible =
      output
      |> pcm_frames()
      |> Enum.find(fn frame -> frame_amplitude(frame) > 0 end)

    assert is_binary(first_audible)
    assert frame_amplitude(first_audible) > context.config.detection_threshold
    assert frame_amplitude(first_audible) < div(context.config.amplitude, 2)
    assert {:ok, decoder} = Decoder.new(context.config)
    assert {:ok, _decoder, events} = Decoder.push(decoder, output)
    assert {:partial, "RECEIVED HI"} in events
  end

  test "an admitted tool survives caller overlap and speaks its result" do
    tools = %{
      "echo_context" => %{
        type: "host",
        tool: "echo_context",
        conversation_mode: "non_blocking"
      }
    }

    context = room(tools)
    push_sts(context, context.pcm)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{} = started}, 5_000
    assert_receive {:test_audio_output, sink, _frame}, 5_000
    assert sink == context.sink

    assert :ok =
             CallEngine.Capability.SpeechToSpeech.push_text(
               context.capability,
               "TOOL echo_context {}"
             )

    assert_receive {:vxpipe_event, %ToolCallStarted{}}, 5_000
    [{call_ref, _pending}] = Map.to_list(:sys.get_state(context.authority).sts_tool_calls)

    assert {:ok, tone} = Encoder.encode(context.config, "I")
    push_sts(context, tone, div(byte_size(context.pcm), 320))
    _discarded_tail = collect_output(sink, [])
    assert :ok = TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_event,
                    %AgentTurnCompleted{correlation_id: correlation_id, outcome: :overlapped}},
                   5_000

    assert correlation_id == started.correlation_id

    settled =
      :sys.replace_state(context.authority, fn state ->
        CallEngine.RoomAuthority.SpeechToSpeech.deliver_tool_result(
          state,
          context.capability,
          call_ref,
          %{"text" => "OK"}
        )
      end)

    assert settled.sts_tool_calls == %{}
    assert_receive {:vxpipe_event, %ToolCallCompleted{}}, 5_000

    output = collect_output(sink, [])
    settle_output(sink, output)
    assert_receive {:vxpipe_event, %TextOutput{text: "RECEIVED I"}}, 5_000

    output = collect_output(sink, [])
    settle_output(sink, output)
    assert_receive {:vxpipe_event, %TextOutput{text: "RECEIVED TEXT OK"}}, 5_000
  end

  defp room(tools \\ %{}, privacy? \\ false) do
    speech = %{provider: "morse", model: "morse-duplex", options: Map.new(@morse)}

    participants = %{
      "caller" => %{
        type: "human",
        connection: %{service: "web", mode: "receive", admission: "start_call"},
        capabilities: %{}
      },
      "assistant" => %{
        type: "agent",
        prompt: "Reply in Morse.",
        tools: tools,
        transfers: [],
        first_message: %{mode: "wait_for_input"},
        capabilities: %{speech_to_speech: speech}
      }
    }

    participants =
      if privacy? do
        Map.put(participants, "privacy", %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{},
          while_present: %{audio_routes: %{}}
        })
      else
        participants
      end

    source = %{
      schema_version: CallSpec.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: participants
    }

    assert {:ok, spec} = CallSpec.new(source, resource_id: "sts-duplex", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "sts-duplex", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-sts-duplex",
               actor_id: "actor-sts-duplex"
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(spec, invocation, %{
               host_tools: %{"echo_context" => CallEngine.STSContextTool}
             })

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    privacy = Map.get(plan.participants, "privacy")
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, opened} = TestCallStartup.start_call(plan)
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: opened.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "source-#{System.unique_integer([:positive])}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _attachment} =
             TestTransferConnection.attach(command, sink, input_track: @track)

    TestCallStartup.await_ready(plan.room_id)
    attachment = TestTransferConnection.attachment(command)

    assert {:ok, %{ingress: ingress}} =
             CallEngine.speech_to_speech_input_configuration(attachment)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(
        opened.incarnation_id,
        agent.participant_id
      )

    assert {:ok, config} = Config.new(@morse)
    assert {:ok, pcm} = Encoder.encode(config, "HI")

    %{
      attachment: attachment,
      command: command,
      sink: sink,
      config: config,
      pcm: pcm,
      capability: capability,
      provider: Session.provider(:sys.get_state(capability).session),
      ingress: ingress,
      authority: authority,
      privacy: if(privacy, do: privacy.participant_id),
      caller: caller.participant_id,
      agent: agent.participant_id
    }
  end

  defp push_sts(context, pcm, sequence_offset \\ 0) do
    for {chunk, sequence} <- Enum.with_index(pcm_chunks(pcm), sequence_offset) do
      identity =
        Map.take(context.command, [
          :tenant_id,
          :room_id,
          :incarnation_id,
          :participant_id,
          :connection_id
        ])

      frame =
        struct!(
          AudioFrame,
          Map.merge(
            identity,
            Map.merge(@track, %{
              payload: chunk,
              sequence_number: sequence,
              timestamp: sequence * 160,
              received_at: System.monotonic_time(:millisecond)
            })
          )
        )

      assert :ok =
               TestTransferConnection.run(context.command, fn ->
                 CallEngine.push_speech_to_speech_audio(context.attachment, frame)
               end)

      _ = :sys.get_state(context.capability)
      assert %{queued: 0, in_flight?: false, dropped: 0} = STSIngress.stats(context.ingress)
    end
  end

  defp pcm_chunks(<<chunk::binary-size(320), rest::binary>>),
    do: [chunk | pcm_chunks(rest)]

  defp pcm_chunks(<<>>), do: []
  defp pcm_chunks(tail), do: [tail]

  defp pcm_frames(<<frame::binary-size(640), rest::binary>>),
    do: [frame | pcm_frames(rest)]

  defp pcm_frames(<<>>), do: []
  defp pcm_frames(tail), do: [tail]

  defp frame_amplitude(frame) do
    for <<sample::little-signed-integer-size(16) <- frame>>, reduce: 0 do
      peak -> max(peak, abs(sample))
    end
  end

  defp await_first_word(context, generated_ms) do
    output = :sys.get_state(context.capability).active_output

    first =
      if output,
        do: Enum.find(output.fragments, fn {_start_ms, _end_ms, text} -> text == "RECEIVED" end)

    case first do
      {_start_ms, end_ms, "RECEIVED"} when generated_ms >= end_ms ->
        {end_ms, generated_ms}

      _pending ->
        receive do
          {:test_audio_output, sink, frame} when sink == context.sink ->
            duration = div(byte_size(frame.payload) * 1_000, 16_000 * 2)
            await_first_word(context, generated_ms + duration)
        after
          10_000 -> flunk("first aligned word did not reach the room sink")
        end
    end
  end

  defp collect_output(sink, frames) do
    receive do
      {:test_audio_output, ^sink, frame} ->
        collect_output(sink, [frame.payload | frames])

      {:test_audio_output_finish, ^sink, _turn} ->
        frames |> Enum.reverse() |> IO.iodata_to_binary()
    after
      10_000 -> flunk("duplex reply did not reach the room sink")
    end
  end

  defp settle_output(sink, output) do
    played = div(byte_size(output) * 1_000, 16_000 * 2)
    assert :ok = TestAudioOutputSink.playback_progress(sink, played, played)
    assert :ok = TestAudioOutputSink.playback_completed(sink)
  end
end
