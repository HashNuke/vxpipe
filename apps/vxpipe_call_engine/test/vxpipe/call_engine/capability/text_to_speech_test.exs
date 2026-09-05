defmodule Vxpipe.CallEngine.Capability.TextToSpeechTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.TestTextToSpeechTransport
  alias Vxpipe.CallEngine.TextToSpeechRequest

  test "streams one request and completes it only after output playout" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    capability = start_capability(maximum_requests: 2)
    assert_receive {:test_tts_transport_started, transport, _connection}

    request = request("turn-1", "Echo: hello", sink)
    assert :ok = TextToSpeech.synthesize(capability, request)

    assert_receive {:test_tts_control, ^transport, speak}
    assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "Echo: hello"}
    assert_receive {:test_tts_control, ^transport, flush}
    assert JSON.decode!(flush) == %{"type" => "Flush"}

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"dg_sp_one"})
    )

    TestTextToSpeechTransport.deliver_audio(transport, <<1, 0, 2, 0>>)

    assert_receive {:test_audio_output, ^sink,
                    %AudioOutputFrame{
                      correlation_id: "turn-1",
                      codec: :linear16,
                      sample_rate: 48_000,
                      channels: 1,
                      payload: <<1, 0, 2, 0>>
                    }}

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"dg_sp_one"})
    )

    assert_receive {:test_audio_output_finish, ^sink, "turn-1"}
    refute_receive {:vxpipe_tts_playback, ^capability, ^request, :completed}

    :ok = TestAudioOutputSink.playback_started(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^request, :started}

    :ok = TestAudioOutputSink.playback_progress(sink, 20, 100)
    assert_receive {:vxpipe_tts_playback, ^capability, ^request, {:progress, 20, 100}}

    :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^request, :completed}
  end

  test "bounds and serializes pending turns until prior playout completes" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    capability = start_capability(maximum_requests: 1)
    assert_receive {:test_tts_transport_started, transport, _connection}

    first = request("turn-1", "one", sink)
    second = request("turn-2", "two", sink)
    third = request("turn-3", "three", sink)

    assert :ok = TextToSpeech.synthesize(capability, first)
    assert :ok = TextToSpeech.synthesize(capability, second)
    assert {:error, :queue_full} = TextToSpeech.synthesize(capability, third)

    assert_receive {:test_tts_control, ^transport, first_speak}
    assert JSON.decode!(first_speak)["text"] == "one"
    assert_receive {:test_tts_control, ^transport, _flush}
    refute_receive {:test_tts_control, ^transport, _payload}

    complete_provider_turn(transport, "dg_sp_one")
    assert_receive {:test_audio_output_finish, ^sink, "turn-1"}
    :ok = TestAudioOutputSink.playback_completed(sink)

    assert_receive {:test_tts_control, ^transport, second_speak}
    assert JSON.decode!(second_speak)["text"] == "two"
  end

  test "interrupts current playout and queued speech before starting replacement speech" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    capability = start_capability(maximum_requests: 2)
    assert_receive {:test_tts_transport_started, transport, _connection}

    first = request("turn-1", "one", sink)
    queued = request("turn-2", "two", sink)
    replacement = request("turn-3", "three", sink)

    assert :ok = TextToSpeech.synthesize(capability, first)
    assert :ok = TextToSpeech.synthesize(capability, queued)
    assert_receive {:test_tts_control, ^transport, _speak}
    assert_receive {:test_tts_control, ^transport, _flush}

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"dg_sp_one"})
    )

    TestTextToSpeechTransport.deliver_audio(transport, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^sink, %AudioOutputFrame{correlation_id: "turn-1"}}

    :ok = TestAudioOutputSink.playback_started(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^first, :started}
    :ok = TestAudioOutputSink.playback_progress(sink, 20, 100)
    assert_receive {:vxpipe_tts_playback, ^capability, ^first, {:progress, 20, 100}}

    assert {:ok, [{^first, 20}, {^queued, 0}]} = TextToSpeech.interrupt(capability)
    assert_receive {:test_audio_output_interrupt, ^sink, "turn-1", 20}

    assert_receive {:test_tts_control, ^transport, interrupt}

    assert JSON.decode!(interrupt) == %{
             "type" => "Interrupt",
             "playback_offset" => %{"type" => "time_ms", "value" => 20}
           }

    TestTextToSpeechTransport.deliver_audio(transport, <<3, 0, 4, 0>>)
    refute_receive {:test_audio_output, ^sink, %AudioOutputFrame{payload: <<3, 0, 4, 0>>}}

    assert :ok = TextToSpeech.synthesize(capability, replacement)
    refute_receive {:test_tts_control, ^transport, _payload}

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"SpeechInterrupted","request_id":"req","audio_played_ms":20,"text_spoken":"o","text_remaining":"ne","metadata":{"speech_id":"dg_sp_one"}})
    )

    assert_receive {:test_tts_control, ^transport, replacement_speak}
    assert JSON.decode!(replacement_speak) == %{"type" => "Speak", "text" => "three"}
    assert_receive {:test_tts_control, ^transport, replacement_flush}
    assert JSON.decode!(replacement_flush) == %{"type" => "Flush"}
  end

  test "interrupts promptly while one bounded audio write is backpressured" do
    sink = start_supervised!({TestAudioOutputSink, observer: self(), block_output: true})
    capability = start_capability(maximum_requests: 1)
    task_supervisor = start_supervised!(Task.Supervisor)
    assert_receive {:test_tts_transport_started, transport, _connection}

    current = request("turn-1", "one", sink)
    assert :ok = TextToSpeech.synthesize(capability, current)
    assert_receive {:test_tts_control, ^transport, _speak}
    assert_receive {:test_tts_control, ^transport, _flush}

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"dg_sp_one"})
    )

    audio_reference =
      TestTextToSpeechTransport.deliver_audio_with_result(transport, <<1, 0, 2, 0>>)

    assert_receive {:test_audio_output, ^sink, %AudioOutputFrame{correlation_id: "turn-1"}}
    :ok = TestAudioOutputSink.playback_started(sink)
    :ok = TestAudioOutputSink.playback_progress(sink, 20, 100)

    interruption =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        TextToSpeech.interrupt(capability)
      end)

    assert Task.await(interruption, 500) == {:ok, [{current, 20}]}
    assert_receive {:test_audio_output_interrupt, ^sink, "turn-1", 20}
    assert_receive {:test_tts_audio_result, ^audio_reference, :ok}
  end

  test "tolerates warnings but stops on provider errors" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    capability = start_capability(maximum_requests: 1)
    monitor = Process.monitor(capability)
    assert_receive {:test_tts_transport_started, transport, _connection}

    assert :ok = TextToSpeech.synthesize(capability, request("turn-1", "one", sink))
    assert_receive {:test_tts_control, ^transport, _speak}
    assert_receive {:test_tts_control, ^transport, _flush}

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"Warning","request_id":"req","code":"SYNTHESIS_RETRYING"})
    )

    _ = :sys.get_state(capability)

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"Error","request_id":"req","code":"MESSAGE_INVALID"})
    )

    assert_receive {:vxpipe_tts_unavailable, ^capability, :provider_failed}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :provider_failed}
  end

  defp start_capability(options) do
    provider =
      FluxTextToSpeech.new!(
        api_key: "test-key",
        model: "flux-haley-en",
        encoding: :linear16,
        sample_rate: 48_000
      )

    start_supervised!(
      {TextToSpeech,
       [
         owner: self(),
         participant_id: "agent-test",
         provider: {FluxTextToSpeech, provider},
         transport: {TestTextToSpeechTransport, [observer: self()]},
         task_supervisor: Vxpipe.CallEngine.AudioOutputTaskSupervisor
       ] ++ options}
    )
  end

  defp request(correlation_id, text, sink) do
    %TextToSpeechRequest{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      participant_id: "agent-test",
      source_participant_id: "human-test",
      connection_id: "connection-test",
      command_id: "command-test",
      correlation_id: correlation_id,
      text: text,
      output_sink: sink
    }
  end

  defp complete_provider_turn(transport, speech_id) do
    TestTextToSpeechTransport.deliver_control(
      transport,
      JSON.encode!(%{"type" => "SpeechStarted", "request_id" => "req", "speech_id" => speech_id})
    )

    TestTextToSpeechTransport.deliver_control(
      transport,
      JSON.encode!(%{
        "type" => "SpeechMetadata",
        "request_id" => "req",
        "speech_id" => speech_id
      })
    )
  end
end
