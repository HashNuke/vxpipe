defmodule Vxpipe.Gateway.Telephony.PhoneRecoverySpeechTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, OutputSink}
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestTextToSpeechTransport
  alias Vxpipe.Gateway.{PhoneHandoffAssertions, TestOpusEncoder}
  alias Vxpipe.Gateway.Media.OutputArbiter
  alias Vxpipe.Gateway.WebRTC.AudioEgress
  alias Vxpipe.Providers.Deepgram.{FluxTextToSpeech, TTSSession}

  for fenced? <- [false, true] do
    test "recovery follows an earlier acknowledgement with fencing #{fenced?}" do
      {session, voice} = start_speech()
      assert {:ok, handle} = Session.speak(session, "Connecting support.")
      request = handle.ref
      assert_receive {:test_tts_control, ^voice, speak}
      assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "Connecting support."}
      assert_receive {:vxpipe_speech, %Event{kind: :input_submitted} = submitted}
      assert :ok = Session.ack(session, submitted)

      if unquote(fenced?) do
        assert {:ok, ticket} = Session.fence_output(session, request)
        assert {:ok, _playback} = Session.cancel(session, ticket, 0)
      end

      observer = self()

      waiter =
        start_supervised!(
          {Task,
           fn ->
             send(self(), {:test_tts_control, voice, speak})

             result =
               PhoneHandoffAssertions.await_recovery_speech(
                 voice,
                 System.monotonic_time(:millisecond) + 2_000
               )

             send(observer, {:recovery_speech_ready, result})
           end}
        )

      if unquote(fenced?) do
        assert_receive {:vxpipe_speech, %Event{kind: :cancelled} = terminal}, 1_000
        assert terminal.request_ref == request
        assert :ok = Session.ack(session, terminal)
        refute_received {:vxpipe_speech_audio, %Audio{request_ref: ^request}}
      else
        assert_receive {:vxpipe_speech_audio, %Audio{request_ref: ^request} = audio}, 1_000
        assert :ok = Session.validate_audio(session, audio)
        assert byte_size(audio.payload) > 0
        {output, native} = start_output()
        assert :ok = OutputSink.push(output, frame(audio.payload))
        assert :ok = Session.ack_audio(session, audio)
        assert_receive {:vxpipe_speech, %Event{kind: :completed} = terminal}, 1_000
        assert terminal.request_ref == request
        assert :ok = Session.ack(session, terminal)
        assert :ok = OutputSink.finish(output, "acknowledgement", self())
        assert_receive {:pace, ^native, tick}
        send(native, tick)
        assert_receive {:vxpipe_audio_playback, ^output, "acknowledgement", {:completed, 20}}
        assert :ok = Session.settle_output(session, handle, 20)
      end

      assert {:ok, %{ref: recovery}} = Session.speak(session, "We can continue.")
      refute recovery == request

      assert_receive {:test_tts_control, ^voice, next_speak}
      assert JSON.decode!(next_speak) == %{"type" => "Flush"}
      assert_receive {:test_tts_control, ^voice, next_speak}
      assert JSON.decode!(next_speak) == %{"type" => "Speak", "text" => "We can continue."}
      send(waiter, {:test_tts_control, voice, next_speak})
      assert_receive {:recovery_speech_ready, :ok}, 1_000
    end
  end

  defp start_speech do
    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = FluxTextToSpeech.new(api_key: "synthetic-phone-key")

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: TTSSession,
               options: [sample_rate: 48_000],
               private: [
                 config: config,
                 wire_module: TestTextToSpeechTransport,
                 wire_options: [observer: self(), ready_on_start: true]
               ]
             )

    assert_receive {:test_tts_transport_started, voice, _connection}, 1_000
    assert_receive {:vxpipe_speech, %Event{kind: :ready} = ready}, 1_000
    assert :ok = Session.ack(session, ready)
    {session, voice}
  end

  defp start_output do
    observer = self()

    native =
      start_supervised!(
        {AudioEgress,
         tenant_id: "tenant",
         room_id: "room",
         incarnation_id: "incarnation",
         participant_id: "caller",
         connection_id: "connection",
         peer_connection: self(),
         track_id: "track",
         encoder: {TestOpusEncoder, [observer: self()]},
         send_rtp: fn _, _, _packet -> :ok end,
         schedule: fn target, message, _delay ->
           send(observer, {:pace, target, message})
           make_ref()
         end}
      )

    output =
      start_supervised!(
        {OutputArbiter,
         tenant_id: "tenant",
         room_id: "room",
         incarnation_id: "incarnation",
         participant_id: "caller",
         connection_id: "connection",
         native_output: native,
         native_adapter: AudioEgress,
         owner: self()}
      )

    {output, native}
  end

  defp frame(payload) do
    %AudioOutputFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "agent",
      connection_id: "connection",
      command_id: "ack-command",
      correlation_id: "acknowledgement",
      codec: :linear16,
      sample_rate: 48_000,
      channels: 1,
      byte_order: :little,
      payload: payload,
      reply_to: self(),
      audio_scope: :private
    }
  end
end
