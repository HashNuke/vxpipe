defmodule Vxpipe.CallEngine.RoomAuthority.STSTranscriptModesTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnInterrupted,
    ParticipantTranscription,
    TextOutput
  }

  alias Vxpipe.CallEngine.Media.{AudioFrame, STSIngress}
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder, Encoder}
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestCallStartup, TestTransferConnection}
  alias Vxpipe.Providers.MorseCode.{STSSession, STTSession}

  @morse [unit_duration_ms: 20]
  @track %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    settings =
      original
      |> Keyword.put(:speech_to_speech, providers: %{STSSession => [enabled: true]})
      |> Keyword.put(:speech_to_text,
        providers: %{
          STTSession => [
            enabled: true,
            media_ingress: [
              maximum_frames: 25,
              maximum_bytes: 65_536,
              maximum_age_ms: 1_000,
              maximum_consecutive_overflows: 3
            ]
          ]
        }
      )

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
  end

  for human_stt? <- [false, true], output_stt? <- [false, true] do
    test "one room round trip with human STT #{human_stt?} and agent-output STT #{output_stt?}" do
      context = room(unquote(human_stt?), unquote(output_stt?))

      if unquote(human_stt?) do
        push_human_stt(context)
        assert_caller_text(context)
      else
        assert context.attachment.media_ingress == nil
      end

      push_sts(context)
      unless unquote(human_stt?), do: assert_caller_text(context)
      output = collect_output(context.sink, [])
      settle_and_assert_reply(context, output)
    end
  end

  test "delayed human recognition onset cannot interrupt a newer provider-driven reply" do
    context = room(true, false)
    assert :ok = :sys.suspend(context.authority)

    output =
      try do
        push_human_stt(context)
        push_sts(context)
        collect_output(context.sink, [])
      after
        :sys.resume(context.authority)
      end

    assert_caller_text(context)
    _ = :sys.get_state(context.authority)
    refute_received {:test_audio_output_interrupt, _, _, _}
    refute_received {:vxpipe_event, %AgentTurnInterrupted{}}
    settle_and_assert_reply(context, output)
  end

  defp room(human_stt?, output_stt?) do
    plan = compile_plan(human_stt?, output_stt?)
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
               connection_id: "source-#{System.unique_integer([:positive])}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink, input_track: @track)
    TestCallStartup.await_ready(plan.room_id)
    attachment = TestTransferConnection.attachment(command)

    assert {:ok, %{ingress: ingress}} =
             CallEngine.speech_to_speech_input_configuration(attachment)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    assert {:ok, config} = Config.new(@morse)
    assert {:ok, pcm} = Encoder.encode(config, "HI")

    %{
      attachment: attachment,
      command: command,
      sink: sink,
      config: config,
      pcm: pcm,
      capability: capability,
      ingress: ingress,
      authority: authority,
      caller: caller.participant_id,
      agent: agent.participant_id
    }
  end

  defp push_human_stt(context) do
    assert is_pid(context.attachment.media_ingress)

    assert :ok =
             TestTransferConnection.run(context.command, fn ->
               CallEngine.push_audio(context.attachment, frame(context, context.pcm, 0))
             end)
  end

  defp push_sts(context) do
    for {chunk, sequence} <-
          Enum.with_index(for <<chunk::binary-size(320) <- context.pcm>>, do: chunk) do
      assert :ok =
               TestTransferConnection.run(context.command, fn ->
                 CallEngine.push_speech_to_speech_audio(
                   context.attachment,
                   frame(context, chunk, sequence)
                 )
               end)

      _ = :sys.get_state(context.capability)
      assert %{queued: 0, in_flight?: false, dropped: 0} = STSIngress.stats(context.ingress)
    end
  end

  defp frame(context, pcm, sequence) do
    identity =
      Map.take(context.command, [
        :tenant_id,
        :room_id,
        :incarnation_id,
        :participant_id,
        :connection_id
      ])

    struct!(
      AudioFrame,
      Map.merge(
        identity,
        Map.merge(@track, %{
          payload: pcm,
          sequence_number: sequence,
          timestamp: sequence * 160,
          received_at: System.monotonic_time(:millisecond)
        })
      )
    )
  end

  defp assert_caller_text(context) do
    caller = context.caller

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{participant_id: ^caller, text: "HI", final: true}},
                   1_000
  end

  defp collect_output(sink, frames) do
    receive do
      {:test_audio_output, ^sink, frame} ->
        collect_output(sink, [frame.payload | frames])

      {:test_audio_output_finish, ^sink, _turn} ->
        frames |> Enum.reverse() |> IO.iodata_to_binary()
    after
      2_000 -> flunk("STS reply did not reach the room sink")
    end
  end

  defp settle_and_assert_reply(context, output) do
    assert {:ok, decoder} = Decoder.new(context.config)
    assert {:ok, _decoder, events} = Decoder.push(decoder, output)
    assert {:final, "RECEIVED HI"} in events
    assert_receive {:vxpipe_event, %AgentSpeechStarted{} = started}, 1_000
    assert String.starts_with?(started.correlation_id, "turn_")
    assert String.starts_with?(started.command_id, "cmd_")
    assert started.connection_id == context.command.connection_id
    refute_received {:vxpipe_event, %TextOutput{}}
    played = div(byte_size(output) * 1_000, 16_000 * 2)
    assert :ok = TestAudioOutputSink.playback_progress(context.sink, played, played)
    assert :ok = TestAudioOutputSink.playback_completed(context.sink)
    agent = context.agent

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      participant_id: ^agent,
                      source_participant_id: ^agent,
                      text: "RECEIVED HI",
                      will_be_spoken: true
                    } = text},
                   1_000

    assert_receive {:vxpipe_event, %AgentTurnCompleted{participant_id: ^agent} = completed}, 1_000
    assert text.correlation_id == started.correlation_id
    assert completed.correlation_id == started.correlation_id
    assert text.command_id == started.command_id
    assert completed.command_id == started.command_id
    _ = :sys.get_state(context.capability)
    _ = :sys.get_state(context.authority)
    _ = TestTransferConnection.run(context.command, fn -> :ok end)
    refute_received {:vxpipe_event, %ParticipantTranscription{final: true}}
    refute_received {:vxpipe_event, %TextOutput{}}
    refute_received {:vxpipe_event, %AgentTurnCompleted{}}
    refute_received {:vxpipe_event, %AgentTurnInterrupted{}}
  end

  defp compile_plan(human_stt?, output_stt?) do
    speech = %{provider: "morse", model: "morse", options: Map.new(@morse)}
    agent = %{speech_to_speech: put_in(speech.options[:output_transcript], not output_stt?)}
    agent = if output_stt?, do: Map.put(agent, :output_speech_to_text, speech), else: agent

    source = %{
      schema_version: CallSpec.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: if(human_stt?, do: %{speech_to_text: speech}, else: %{})
        },
        "assistant" => %{
          type: "agent",
          prompt: "Reply in Morse.",
          tools: %{},
          transfers: [],
          first_message: %{mode: "wait_for_input"},
          capabilities: agent
        }
      }
    }

    assert {:ok, spec} = CallSpec.new(source, resource_id: "sts-modes", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "sts-modes", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-sts-modes",
               actor_id: "actor-sts-modes"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end
end
