defmodule Vxpipe.CallEngine.SpeechExpansionRoomTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallInvocation,
    CallSpec,
    CallSpecCompiler,
    TestCallStartup,
    TestEchoModelProvider,
    TestTenantCredentialSource,
    TestTransferConnection,
    TestTurnCall
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    AgentTurnInterrupted,
    ParticipantTranscription,
    TextOutput
  }

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestRoomTTSRequest}
  alias Vxpipe.CallEngine.TestCartesiaSTTTransport, as: CartesiaWire
  alias Vxpipe.Providers.Cartesia.{STTSession, TTSSession}
  alias Vxpipe.Providers.ElevenLabs.TTSSession, as: ElevenLabsTTS

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    Process.register(self(), TestRoomTTSRequest.Observer)

    providers =
      Map.new(
        [TTSSession, ElevenLabsTTS],
        &{&1, [enabled: true, request_module: TestRoomTTSRequest, maximum_requests: 4]}
      )

    activity =
      Keyword.update!(
        original,
        :agent_runtime,
        &Keyword.put(&1, :fixture, {TestEchoModelProvider, []})
      )

    activity = Keyword.put(activity, :text_to_speech, providers: providers)

    activity =
      Keyword.put(activity, :speech_to_text,
        providers: %{
          STTSession => [
            enabled: true,
            wire_module: CartesiaWire,
            wire_options: [observer: self()],
            media_ingress: [
              maximum_frames: 50,
              maximum_bytes: 262_144,
              maximum_age_ms: 2_000,
              maximum_consecutive_overflows: 5
            ]
          ]
        }
      )

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, activity)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  for {provider, model, voice} <- [
        {"cartesia", "sonic-3.6", "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4"},
        {"elevenlabs", "eleven_flash_v2_5", "JBFqnCBsd6RMkjVDRZzb"}
      ] do
    @tag selection: %{provider: provider, model: model, options: %{voice: voice}}
    test "#{provider} compiled room finishes speech only after credited playout", %{
      selection: selection
    } do
      {plan, room} = start_room(selection)
      sink = start_supervised!({TestAudioOutputSink, observer: self()})
      attach(plan, room, sink)
      first = command(plan, room, "first", "hello")
      assert :ok = TestTransferConnection.send_text(first)

      assert_receive {:vxpipe_event, %TextOutput{correlation_id: "first", text: "Echo: hello"}},
                     2_000

      assert_receive {:room_tts_request, worker, "Echo: hello"}, 2_000
      pcm = :binary.copy(<<1, 0>>, 320)
      send(worker, {:audio, pcm})
      assert_receive {:test_audio_output, ^sink, %{correlation_id: "first", payload: ^pcm}}, 2_000
      assert_receive {:room_tts_consumed, ^worker, :ok}, 2_000
      send(worker, :complete)
      assert_receive {:test_audio_output_finish, ^sink, "first"}, 2_000
      refute_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "first"}}, 30
      assert :ok = TestAudioOutputSink.playback_completed(sink)
      assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "first"}}, 2_000
    end

    @tag selection: %{provider: provider, model: model, options: %{voice: voice}}
    test "#{provider} compiled room interruption retires synthesis before replacement", %{
      selection: selection
    } do
      {plan, room} = start_room(selection)
      sink = start_supervised!({TestAudioOutputSink, observer: self()})
      attach(plan, room, sink)
      assert :ok = TestTransferConnection.send_text(command(plan, room, "first", "hello"))
      assert_receive {:room_tts_request, worker, "Echo: hello"}, 2_000
      monitor = Process.monitor(worker)
      send(worker, {:audio, :binary.copy(<<1, 0>>, 320)})
      assert_receive {:test_audio_output, ^sink, %{correlation_id: "first"}}, 2_000
      assert_receive {:room_tts_consumed, ^worker, :ok}, 2_000
      assert :ok = TestAudioOutputSink.playback_started(sink)
      assert :ok = TestTransferConnection.send_text(command(plan, room, "second", "change"))
      assert_receive {:test_audio_output_interrupt, ^sink, "first", _played_ms}, 2_000
      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 2_000

      assert_receive {:vxpipe_event,
                      %AgentTurnInterrupted{
                        correlation_id: "first",
                        interruption_correlation_id: "second"
                      }},
                     2_000

      assert_receive {:room_tts_request, next, "Echo: change"}, 2_000
      refute next == worker
      send(worker, {:audio, <<99, 0>>})
      send(worker, :complete)
      refute_receive {:test_audio_output, ^sink, %{payload: <<99, 0>>}}, 30
      send(next, {:audio, <<2, 0>>})

      assert_receive {:test_audio_output, ^sink, %{correlation_id: "second", payload: <<2, 0>>}},
                     2_000

      assert_receive {:room_tts_consumed, ^next, :ok}, 2_000
      send(next, :complete)
      assert_receive {:test_audio_output_finish, ^sink, "second"}, 2_000
      assert :ok = TestAudioOutputSink.playback_completed(sink)
      assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "second"}}, 2_000
      refute_received {:vxpipe_event, %AgentTurnCompleted{correlation_id: "first"}}
    end
  end

  test "compiled Cartesia caller ingress publishes cumulative final room text" do
    source = TestTurnCall.call_spec(speech_to_text: %{provider: "cartesia", model: "ink-2"})
    source = Map.put(source, :media_policy, %{save_transcripts: true})
    {plan, room} = compile_start(source, "cartesia")
    attachment = attach(plan, room, nil, false)
    assert_receive {:cartesia_stt_started, wire, _config}, 2_000

    assert :ok =
             Ingress.prepare_track(attachment.media_ingress, %{
               track_id: "provider-room",
               codec: :linear16,
               sample_rate: 16_000,
               channels: 1
             })

    assert {:ok, resources} = Ingress.readiness_resources(attachment.media_ingress)
    resource = Enum.find(resources, &(&1.kind == :speech_to_text))

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "cartesia-room",
         resources: [resource],
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert :ok = CartesiaWire.deliver(wire, %{type: "connected", request_id: "room"})
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000
    TestCallStartup.await_ready(plan.room_id)
    participant = Map.fetch!(plan.participants, plan.entry_caller).participant_id

    assert :ok =
             CallEngine.push_audio(attachment, %AudioFrame{
               tenant_id: plan.tenant_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant,
               connection_id: "room-caller",
               track_id: "provider-room",
               codec: :linear16,
               sample_rate: 16_000,
               channels: 1,
               sequence_number: 0,
               timestamp: 0,
               payload: <<1, 0>>,
               received_at: System.monotonic_time(:millisecond)
             })

    assert_receive {:cartesia_stt_audio, ^wire, <<1, 0>>}, 2_000
    assert :ok = CartesiaWire.deliver(wire, %{type: "turn.start", request_id: "room"})

    assert :ok =
             CartesiaWire.deliver(wire, %{
               type: "turn.update",
               request_id: "room",
               transcript: "Public"
             })

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      final: false,
                      text: "Public",
                      provider_turn_index: 0
                    }},
                   2_000

    assert :ok =
             CartesiaWire.deliver(wire, %{
               type: "turn.end",
               request_id: "room",
               transcript: "Public telescope."
             })

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      final: true,
                      text: "Public telescope.",
                      provider_turn_index: 0
                    }},
                   2_000

    assert_receive {:vxpipe_event, %TextOutput{text: "Echo: Public telescope."}}, 2_000
  end

  defp start_room(selection) do
    source = TestTurnCall.call_spec()

    participants =
      Map.update!(source.participants, "receiver", fn receiver ->
        %{receiver | capabilities: Map.put(receiver.capabilities, :text_to_speech, selection)}
      end)

    compile_start(%{source | participants: participants}, selection.provider)
  end

  defp compile_start(source, provider) do
    assert {:ok, spec} = CallSpec.new(source, resource_id: "speech-expansion-room", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "speech-expansion-room", revision: 1},
                 transport: %{type: "web"}
               },
               tenant_id: "speech-expansion-test",
               actor_id: "speech-expansion-test"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    bindings = %{{plan.tenant_id, provider, "default"} => %{"api_key" => "synthetic-room-key"}}

    assert {:ok, room} =
             TestCallStartup.start_call(plan,
               credential_source: {TestTenantCredentialSource, {self(), bindings}}
             )

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    on_exit(fn ->
      try do
        GenServer.stop(authority, :shutdown)
      catch
        :exit, {:noproc, _call} -> :ok
      end
    end)

    {plan, room}
  end

  defp attach(plan, room, sink, await? \\ true) do
    participant = Map.fetch!(plan.participants, plan.entry_caller).participant_id

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant,
               connection_id: "room-caller",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, attachment} =
             TestTransferConnection.attach(command, sink,
               input_track: %{
                 track_id: "provider-room",
                 codec: :linear16,
                 sample_rate: 16_000,
                 channels: 1
               }
             )

    if await?, do: TestCallStartup.await_ready(plan.room_id)
    attachment
  end

  defp command(plan, room, correlation, text) do
    participant = Map.fetch!(plan.participants, plan.entry_caller).participant_id

    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant,
               connection_id: "room-caller",
               correlation_id: correlation,
               content: text,
               audio_response: true,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    command
  end
end
