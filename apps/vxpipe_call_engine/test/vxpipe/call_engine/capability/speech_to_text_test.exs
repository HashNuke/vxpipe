defmodule Vxpipe.CallEngine.Capability.SpeechToTextTest do
  use ExUnit.Case, async: true

  @moduletag capture_log: true

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.Deepgram.Flux
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.TestSpeechToTextTransport

  test "validates audio and relays normalized provider signals without raw payloads" do
    assert {:ok, provider} =
             Flux.new(
               api_key: "runtime-secret",
               model: "flux-general-en",
               encoding: :opus,
               sample_rate: 48_000
             )

    identity = [
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo"
    ]

    capability =
      start_supervised!(
        {SpeechToText,
         identity ++
           [
             owner: self(),
             provider: {Flux, provider},
             transport: {TestSpeechToTextTransport, [observer: self()]}
           ]}
      )

    assert_receive {:test_stt_transport_started, transport,
                    %{
                      url: url,
                      headers: [{"Authorization", "Token runtime-secret"}]
                    }}

    refute url =~ "runtime-secret"

    unsupported = audio_frame(identity, codec: :linear16)
    assert {:error, :unsupported_audio} = SpeechToText.push_audio(capability, unsupported)
    refute_receive {:test_stt_audio, ^transport, _audio}

    frame = audio_frame(identity)
    assert :ok = SpeechToText.push_audio(capability, frame)
    assert_receive {:test_stt_audio, ^transport, <<1, 2, 3>>}

    payload = turn_message("StartOfTurn", 1, "hello")
    TestSpeechToTextTransport.deliver(transport, payload)

    assert_receive {:vxpipe_stt_signal, ^capability,
                    %{
                      tenant_id: "tenant-demo",
                      room_id: "room-demo",
                      incarnation_id: "rinc-demo",
                      participant_id: "part-human",
                      connection_id: "conn-demo"
                    }, %Signal{kind: :turn_started, text: "hello", provider_sequence: 1}}

    refute_receive {:vxpipe_stt_signal, ^capability, _, ^payload}
  end

  test "ignores repeated provider sequence numbers and terminates on transport failure" do
    {capability, transport} = start_capability()
    payload = turn_message("Update", 4, "hello")

    TestSpeechToTextTransport.deliver(transport, payload)
    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{provider_sequence: 4}}

    TestSpeechToTextTransport.deliver(transport, payload)
    refute_receive {:vxpipe_stt_signal, ^capability, _, %Signal{provider_sequence: 4}}

    monitor = Process.monitor(capability)
    TestSpeechToTextTransport.disconnect(transport, :closed)

    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :transport_closed}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :transport_closed}
  end

  test "does not turn malformed provider messages into domain signals" do
    {capability, transport} = start_capability()
    monitor = Process.monitor(capability)
    TestSpeechToTextTransport.deliver(transport, ~s({"type":"TurnInfo"}))

    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :invalid_provider_message}
    assert_receive {:DOWN, ^monitor, :process, ^capability, :invalid_provider_message}
    refute_receive {:vxpipe_stt_signal, ^capability, _, _}
  end

  defp start_capability do
    assert {:ok, provider} =
             Flux.new(
               api_key: "runtime-secret",
               model: "flux-general-en",
               encoding: :opus,
               sample_rate: 48_000
             )

    capability =
      start_supervised!(
        {SpeechToText,
         owner: self(),
         tenant_id: "tenant-demo",
         room_id: "room-demo",
         incarnation_id: "rinc-demo",
         participant_id: "part-human",
         connection_id: "conn-demo",
         provider: {Flux, provider},
         transport: {TestSpeechToTextTransport, [observer: self()]}}
      )

    assert_receive {:test_stt_transport_started, transport, _connection}
    {capability, transport}
  end

  defp audio_frame(identity, overrides \\ []) do
    fields =
      identity ++
        [
          track_id: "track-audio",
          codec: :opus,
          sample_rate: 48_000,
          channels: 1,
          sequence_number: 12,
          timestamp: 960,
          payload: <<1, 2, 3>>,
          received_at: 1_788_000_000_000
        ]

    struct!(AudioFrame, Keyword.merge(fields, overrides))
  end

  defp turn_message(event, sequence, transcript) do
    JSON.encode!(%{
      "type" => "TurnInfo",
      "request_id" => "request-1",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    })
  end
end
