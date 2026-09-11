defmodule Vxpipe.Gateway.WebRTC.AudioPipelineTest do
  use ExUnit.Case, async: true

  alias Membrane.Opus.Encoder.Native
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.Gateway.Media.PCMFrame
  alias Vxpipe.Gateway.WebRTC.AudioPipeline

  @application_voip 2_048
  @automatic_bitrate -1_000
  @pipeline_timeout 2_000
  @signal_voice 3_001

  test "uses the Membrane chain to decode and rechunk Opus on the shared room clock" do
    pipeline_id = start_pipeline()
    packet = encode(:binary.copy(<<1_000::little-signed-16>>, 960), 1, 960)

    assert :ok = AudioPipeline.push(pipeline_id, frame(7, 96_000, 1_043, packet))

    assert_receive {:vxpipe_audio_pipeline, ^pipeline_id,
                    %PCMFrame{
                      track_id: "track-a",
                      timestamp: 1_920,
                      sample_rate: 48_000,
                      channels: 1,
                      payload: pcm
                    }},
                   @pipeline_timeout

    assert byte_size(pcm) == 1_920
  end

  test "lets Membrane accumulate two 10 ms packets into one exact mixer frame" do
    pipeline_id = start_pipeline()
    first = encode(:binary.copy(<<500::little-signed-16>>, 480), 1, 480)
    second = encode(:binary.copy(<<700::little-signed-16>>, 480), 1, 480)

    assert :ok = AudioPipeline.push(pipeline_id, frame(10, 5_000, 1_000, first))
    refute_receive {:vxpipe_audio_pipeline, ^pipeline_id, %PCMFrame{}}, 50

    assert :ok = AudioPipeline.push(pipeline_id, frame(11, 5_480, 1_010, second))

    assert_receive {:vxpipe_audio_pipeline, ^pipeline_id, %PCMFrame{timestamp: 0, payload: pcm}},
                   @pipeline_timeout

    assert byte_size(pcm) == 1_920
  end

  test "uses the Membrane pipeline to downmix stereo Opus" do
    pipeline_id = start_pipeline()

    stereo_pcm =
      IO.iodata_to_binary(
        List.duplicate(<<1_000::little-signed-16, -500::little-signed-16>>, 960)
      )

    packet = encode(stereo_pcm, 2, 960)
    assert :ok = AudioPipeline.push(pipeline_id, frame(15, 8_000, 1_020, packet))

    assert_receive {:vxpipe_audio_pipeline, ^pipeline_id, %PCMFrame{channels: 1, payload: pcm}},
                   @pipeline_timeout

    assert byte_size(pcm) == 1_920
  end

  test "rejects transport input outside the pipeline's pinned identity and track" do
    pipeline_id = start_pipeline()
    packet = encode(:binary.copy(<<1_000::little-signed-16>>, 960), 1, 960)
    input = frame(7, 96_000, 1_043, packet)

    assert {:error, :wrong_connection} =
             AudioPipeline.push(pipeline_id, %{input | connection_id: "conn-other"})

    assert {:error, :wrong_tenant} =
             AudioPipeline.push(pipeline_id, %{input | tenant_id: "tenant-other"})

    assert {:error, :wrong_room} =
             AudioPipeline.push(pipeline_id, %{input | room_id: "room-other"})

    assert {:error, :wrong_incarnation} =
             AudioPipeline.push(pipeline_id, %{input | incarnation_id: "rinc-other"})

    assert {:error, :wrong_participant} =
             AudioPipeline.push(pipeline_id, %{input | participant_id: "part-other"})

    assert :ok = AudioPipeline.push(pipeline_id, input)

    assert {:error, :wrong_track} =
             AudioPipeline.push(pipeline_id, %{input | sequence_number: 8, track_id: "track-b"})
  end

  defp start_pipeline do
    pipeline_id = "audio-pipeline-#{System.unique_integer([:positive, :monotonic])}"

    _supervisor =
      start_supervised!(
        {AudioPipeline,
         pipeline_id: pipeline_id,
         owner: self(),
         tenant_id: "tenant-demo",
         room_id: "room-demo",
         incarnation_id: "rinc-demo",
         participant_id: "part-human",
         connection_id: "conn-demo",
         clock_origin_ms: 1_000,
         jitter_latency: 0}
      )

    assert_receive {:vxpipe_audio_pipeline_ready, ^pipeline_id}, @pipeline_timeout
    pipeline_id
  end

  defp encode(pcm, channels, frame_samples) do
    encoder =
      Native.create(
        48_000,
        channels,
        @application_voip,
        @automatic_bitrate,
        @signal_voice
      )

    assert {:ok, packet} = Native.encode_packet(encoder, pcm, frame_samples)
    packet
  end

  defp frame(sequence_number, timestamp, received_at, payload) do
    %AudioFrame{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo",
      track_id: "track-a",
      codec: :opus,
      sample_rate: 48_000,
      channels: 2,
      sequence_number: sequence_number,
      timestamp: timestamp,
      payload: payload,
      received_at: received_at
    }
  end
end
