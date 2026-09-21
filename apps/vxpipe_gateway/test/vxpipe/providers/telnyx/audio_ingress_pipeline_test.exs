defmodule Vxpipe.Providers.Telnyx.AudioIngressPipelineTest do
  use ExUnit.Case, async: true

  alias Membrane.Opus.Encoder.Native
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.Gateway.Media.PCMFrame
  alias Vxpipe.Providers.Telnyx.AudioIngressPipeline

  @application_voip 2_048
  @automatic_bitrate -1_000
  @pipeline_timeout 5_000
  @signal_voice 3_001

  test "decodes Telnyx Opus into room-aligned 48 kHz mono PCM without FFmpeg" do
    pipeline_id = start_pipeline()
    packet = encode(:binary.copy(<<1_000::little-signed-16>>, 320))

    assert :ok = AudioIngressPipeline.push(pipeline_id, frame(4, 60, 1_043, packet))

    assert_receive {:vxpipe_audio_pipeline, ^pipeline_id,
                    %PCMFrame{
                      track_id: "stream-1",
                      timestamp: 1_920,
                      sample_rate: 48_000,
                      channels: 1,
                      payload: pcm
                    }},
                   @pipeline_timeout

    assert byte_size(pcm) == 1_920
  end

  test "collects the initialized phone input before any media without changing its pinned format" do
    pipeline_id = start_pipeline()
    track = %{track_id: "stream-1", codec: :opus, sample_rate: 16000, channels: 1}
    assert :ok = AudioIngressPipeline.prepare_track(pipeline_id, track)
    assert {:ok, resource, _status} = AudioIngressPipeline.readiness(pipeline_id)
    assert resource.kind == :audio_input
    assert resource.scope == {:participant, "part-human"}
    assert resource.binding == "conn-demo"

    collector =
      start_supervised!(
        {Vxpipe.CallEngine.Readiness.Collector,
         owner: self(),
         incarnation_id: "rinc-demo",
         attempt_id: "phone-input",
         resources: [resource],
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, @pipeline_timeout
    assert {:ok, ^resource, :ready} = AudioIngressPipeline.readiness(pipeline_id)
    assert :ok = AudioIngressPipeline.prepare_track(pipeline_id, track)

    assert {:error, :wrong_track} =
             AudioIngressPipeline.prepare_track(pipeline_id, %{track | track_id: "other"})

    assert {:error, :unsupported_audio} =
             AudioIngressPipeline.prepare_track(pipeline_id, %{track | sample_rate: 48_000})

    assert {:ok, ^resource, :ready} = AudioIngressPipeline.readiness(pipeline_id)
    refute_receive {:vxpipe_audio_pipeline, ^pipeline_id, %PCMFrame{}}
  end

  test "rejects another identity, format, track, or stale provider chunk" do
    pipeline_id = start_pipeline()
    packet = encode(:binary.copy(<<1_000::little-signed-16>>, 320))
    input = frame(4, 60, 1_043, packet)

    assert {:error, :wrong_connection} =
             AudioIngressPipeline.push(pipeline_id, %{input | connection_id: "conn-other"})

    assert {:error, :wrong_tenant} =
             AudioIngressPipeline.push(pipeline_id, %{input | tenant_id: "tenant-other"})

    assert {:error, :wrong_room} =
             AudioIngressPipeline.push(pipeline_id, %{input | room_id: "room-other"})

    assert {:error, :wrong_incarnation} =
             AudioIngressPipeline.push(pipeline_id, %{input | incarnation_id: "rinc-other"})

    assert {:error, :wrong_participant} =
             AudioIngressPipeline.push(pipeline_id, %{input | participant_id: "part-other"})

    assert {:error, :wrong_track} =
             AudioIngressPipeline.push(pipeline_id, %{input | track_id: "stream-other"})

    assert {:error, :unsupported_audio} =
             AudioIngressPipeline.push(pipeline_id, %{input | sample_rate: 48_000})

    assert :ok = AudioIngressPipeline.push(pipeline_id, input)

    assert {:error, :stale_sequence} =
             AudioIngressPipeline.push(pipeline_id, %{input | timestamp: 80})

    assert {:error, :stale_timestamp} =
             AudioIngressPipeline.push(pipeline_id, %{
               input
               | sequence_number: 5,
                 timestamp: 40
             })
  end

  defp start_pipeline do
    pipeline_id = unique_id("telnyx-audio-ingress")

    _supervisor =
      start_supervised!(
        {AudioIngressPipeline,
         pipeline_id: pipeline_id,
         owner: self(),
         tenant_id: "tenant-demo",
         room_id: "room-demo",
         incarnation_id: "rinc-demo",
         participant_id: "part-human",
         connection_id: "conn-demo",
         track_id: "stream-1",
         clock_origin_ms: 1_000}
      )

    assert_receive {:vxpipe_audio_pipeline_ready, ^pipeline_id}, @pipeline_timeout
    pipeline_id
  end

  defp encode(pcm) do
    encoder =
      Native.create(
        16_000,
        1,
        @application_voip,
        @automatic_bitrate,
        @signal_voice
      )

    assert {:ok, packet} = Native.encode_packet(encoder, pcm, 320)
    packet
  end

  defp frame(sequence_number, timestamp, received_at, payload) do
    %AudioFrame{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo",
      track_id: "stream-1",
      codec: :opus,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: sequence_number,
      timestamp: timestamp,
      payload: payload,
      received_at: received_at
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
