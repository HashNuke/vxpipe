defmodule Vxpipe.CallEngine.Media.IngressTest do
  use ExUnit.Case, async: true

  @moduletag capture_log: true

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.{AudioFrame, Ingress}
  alias Vxpipe.CallEngine.Provider.Deepgram.Flux
  alias Vxpipe.CallEngine.TestSpeechToTextTransport

  @identity [
    tenant_id: "tenant-demo",
    room_id: "room-demo",
    incarnation_id: "rinc-demo",
    participant_id: "part-human",
    connection_id: "conn-demo"
  ]

  test "bounds queued audio while preserving accepted frame order" do
    {capability, transport} = start_capability(send_mode: :manual)

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             owner: self(),
             maximum_frames: 2,
             maximum_bytes: 6,
             maximum_age_ms: 1_000,
             maximum_consecutive_overflows: 3,
             clock: fn -> 1_000 end
           ]}
      )

    assert :ok = Ingress.push(ingress, audio_frame(1, <<1, 1, 1>>))
    assert_receive {:test_stt_audio, ^transport, <<1, 1, 1>>}

    assert :ok = Ingress.push(ingress, audio_frame(2, <<2, 2, 2>>))
    assert {:error, :queue_full} = Ingress.push(ingress, audio_frame(3, <<3>>))

    TestSpeechToTextTransport.allow_audio(transport)
    assert_receive {:test_stt_audio, ^transport, <<2, 2, 2>>}

    TestSpeechToTextTransport.allow_audio(transport)
    assert_receive {:vxpipe_media_ingress, ^ingress, {:delivered, 2}}
  end

  test "rejects stale and wrongly scoped frames before provider delivery" do
    {capability, transport} = start_capability()

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             owner: self(),
             maximum_frames: 2,
             maximum_bytes: 32,
             maximum_age_ms: 100,
             maximum_consecutive_overflows: 2,
             clock: fn -> 1_000 end
           ]}
      )

    assert {:error, :stale_frame} =
             Ingress.push(ingress, audio_frame(1, <<1>>, received_at: 899))

    assert {:error, :wrong_connection} =
             Ingress.push(ingress, audio_frame(2, <<2>>, connection_id: "conn-other"))

    refute_receive {:test_stt_audio, ^transport, _audio}
  end

  test "binds the stream to the first accepted audio track" do
    {capability, transport} = start_capability(send_mode: :manual)

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             maximum_frames: 2,
             maximum_bytes: 32,
             maximum_age_ms: 1_000,
             maximum_consecutive_overflows: 2,
             clock: fn -> 1_000 end
           ]}
      )

    assert :ok = Ingress.push(ingress, audio_frame(1, <<1>>))
    assert_receive {:test_stt_audio, ^transport, <<1>>}

    assert {:error, :wrong_track} =
             Ingress.push(ingress, audio_frame(2, <<2>>, track_id: "track-other"))
  end

  test "drops a queued frame that ages out before delivery" do
    clock = start_supervised!({Agent, fn -> 1_000 end})
    {capability, transport} = start_capability(send_mode: :manual)

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             owner: self(),
             maximum_frames: 2,
             maximum_bytes: 6,
             maximum_age_ms: 100,
             maximum_consecutive_overflows: 3,
             clock: fn -> Agent.get(clock, & &1) end
           ]}
      )

    assert :ok = Ingress.push(ingress, audio_frame(1, <<1, 1, 1>>))
    assert_receive {:test_stt_audio, ^transport, <<1, 1, 1>>}
    assert :ok = Ingress.push(ingress, audio_frame(2, <<2, 2, 2>>))

    Agent.update(clock, fn _now -> 1_101 end)
    TestSpeechToTextTransport.allow_audio(transport)

    assert_receive {:vxpipe_media_ingress, ^ingress, {:dropped, :stale, 2}}
    refute_receive {:test_stt_audio, ^transport, <<2, 2, 2>>}
  end

  test "fails the STT stream after sustained overflow" do
    {capability, transport} = start_capability(send_mode: :manual)
    capability_monitor = Process.monitor(capability)

    ingress =
      start_supervised!(
        {Ingress,
         @identity ++
           [
             capability: capability,
             owner: self(),
             maximum_frames: 1,
             maximum_bytes: 3,
             maximum_age_ms: 1_000,
             maximum_consecutive_overflows: 2,
             clock: fn -> 1_000 end
           ]}
      )

    ingress_monitor = Process.monitor(ingress)

    assert :ok = Ingress.push(ingress, audio_frame(1, <<1, 1, 1>>))
    assert_receive {:test_stt_audio, ^transport, <<1, 1, 1>>}
    assert {:error, :queue_full} = Ingress.push(ingress, audio_frame(2, <<2>>))
    assert {:error, :media_overloaded} = Ingress.push(ingress, audio_frame(3, <<3>>))

    assert_receive {:DOWN, ^ingress_monitor, :process, ^ingress, :media_overloaded}

    TestSpeechToTextTransport.allow_audio(transport)
    assert_receive {:vxpipe_stt_unavailable, ^capability, _, :media_overloaded}
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, :media_overloaded}
  end

  defp start_capability(transport_options \\ []) do
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
         @identity ++
           [
             owner: self(),
             provider: {Flux, provider},
             transport:
               {TestSpeechToTextTransport, Keyword.put(transport_options, :observer, self())}
           ]}
      )

    assert_receive {:test_stt_transport_started, transport, _connection}
    {capability, transport}
  end

  defp audio_frame(sequence, payload, overrides \\ []) do
    fields =
      @identity ++
        [
          track_id: "track-audio",
          codec: :opus,
          sample_rate: 48_000,
          channels: 1,
          sequence_number: sequence,
          timestamp: sequence * 960,
          payload: payload,
          received_at: 1_000
        ]

    struct!(AudioFrame, Keyword.merge(fields, overrides))
  end
end
