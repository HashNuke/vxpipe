defmodule Vxpipe.Gateway.Media.DiagnosticAudioMappingTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
  alias ExWebRTC.RTPCodecParameters
  alias Membrane.Opus.Encoder.Native
  alias Vxpipe.CallEngine.Diagnostics.AudioTimeline
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility
  alias Vxpipe.Gateway.Session.Snapshot
  alias Vxpipe.Gateway.Telephony.IncomingAudio
  alias Vxpipe.Gateway.WebRTC.SpeechInput
  alias Vxpipe.Gateway.WebRTC.AudioFrame, as: RTPFrame

  # Carrier cases exercise the existing local mono 16 kHz Opus envelope only.
  # No provider configuration, socket or live call is involved.
  for {transport, codec, rate} <- [
        {:webrtc, :linear16, 16_000},
        {:webrtc, :linear16, 48_000},
        {:webrtc, :opus, 48_000},
        {:carrier, :linear16, 16_000},
        {:carrier, :linear16, 48_000},
        {:carrier, :linear16, 8_000}
      ] do
    @profile {transport, codec, rate}

    test "#{transport} #{codec}/#{rate} preserves receipt time, sample units and loss" do
      {normalize, source} = input(@profile)
      incoming = source.(0, 1_020)
      first = normalize.(incoming)
      assert first.source_epoch == incoming.source_epoch
      timeline = AudioTimeline.new("clock", "source", first.source_epoch, 1_000_000)

      assert first.received_at == 1_020
      assert {:ok, timeline, pcm, []} = AudioTimeline.push(timeline, first)
      assert byte_size(pcm) == 640
      assert {:ok, %{offset_us: 0}} = AudioTimeline.at(timeline, 0)
      assert {:ok, %{offset_us: 20_000}} = AudioTimeline.at(timeline, 320)
      assert {:duplicate, ^timeline} = AudioTimeline.push(timeline, first)

      # Skip the second packet. The normalized gap must remain exactly 20 ms.
      third = normalize.(source.(2, 1_060))
      assert third.timestamp == div(2 * elem(@profile, 2), 50)
      assert third.source_epoch == first.source_epoch
      assert {:ok, timeline, pcm, [:audio_gap]} = AudioTimeline.push(timeline, third)
      assert byte_size(pcm) == 640
      assert {:error, :unobserved_audio} = AudioTimeline.at(timeline, 480)
      assert {:ok, %{offset_us: 60_000}} = AudioTimeline.at(timeline, 960)

      # Late packet arrival cannot fill the discarded gap or move the run clock.
      late = normalize.(source.(1, 1_080))
      assert {:error, :out_of_order} = AudioTimeline.push(timeline, late)
      assert {:error, :unobserved_audio} = AudioTimeline.at(timeline, 480)

      fourth = normalize.(source.(3, 1_065))
      assert {:ok, uncertain, _, []} = AudioTimeline.push(timeline, fourth)
      assert {:error, :clock_uncertain} = AudioTimeline.at(uncertain, 1_280)
    end

    test "#{transport} #{codec}/#{rate} cannot stitch source or clock resets" do
      {normalize, source} = input(@profile)
      incoming = source.(1, 1_040)
      first = normalize.(incoming)
      assert first.source_epoch == incoming.source_epoch
      timeline = AudioTimeline.new("clock", "source", first.source_epoch, 1_000_000)
      assert {:ok, timeline, _, []} = AudioTimeline.push(timeline, first)

      reset = normalize.(%{source.(0, 1_060) | sequence_number: 3})
      assert {:error, :out_of_order} = AudioTimeline.push(timeline, reset)

      next = normalize.(source.(2, 1_060))

      assert {:error, :out_of_order} =
               AudioTimeline.push(timeline, %{next | received_at: 1_030})

      replacement = %{source.(0, 2_020) | source_epoch: make_ref()}
      successor = normalize.(replacement)
      assert successor.source_epoch == replacement.source_epoch
      assert {:error, :source_mismatch} = AudioTimeline.push(timeline, successor)
      fresh = AudioTimeline.new("fresh-clock", "fresh-source", successor.source_epoch, 2_000_000)
      assert {:ok, fresh, _, []} = AudioTimeline.push(fresh, successor)
      assert {:ok, %{clock_id: "fresh-clock", offset_us: 20_000}} = AudioTimeline.at(fresh, 320)
      assert {:error, :source_mismatch} = AudioTimeline.push(fresh, first)
    end
  end

  test "an unsupported diagnostic rate is rejected even when carrier conversion succeeds" do
    {normalize, source} = input({:carrier, :linear16, 22_050})
    frame = normalize.(source.(0, 1_020))
    assert frame.sample_rate == 22_050
    assert byte_size(frame.payload) == 882
    timeline = AudioTimeline.new("clock", "source", frame.source_epoch, 1_000_000)
    assert {:error, :unsupported_audio} = AudioTimeline.push(timeline, frame)
    assert {:error, :unobserved_audio} = AudioTimeline.at(timeline, 320)
  end

  defp input({transport, codec, rate}) do
    source_rate = if transport == :webrtc, do: 48_000, else: 16_000
    channels = if transport == :webrtc, do: 2, else: 1
    samples = div(source_rate, 50)
    encoder = Native.create(source_rate, channels, 2_048, 64_000, 3_001)
    pcm = :binary.copy(<<1_000::little-signed-16>>, samples * channels)
    assert {:ok, payload} = Native.encode_packet(encoder, pcm, samples)
    epoch = make_ref()

    source = fn index, receipt ->
      source_frame(transport, source_rate, channels, payload, index, receipt, epoch)
    end

    target = %{codec: codec, sample_rate: rate, channels: 1}
    example = source.(0, 1_020)

    normalize =
      if transport == :webrtc do
        track = Map.take(example, [:track_id, :codec, :sample_rate, :channels])
        assert {:ok, _output, input} = SpeechInput.configure(track, target)

        fn frame ->
          assert {:ok, normalized} = SpeechInput.frame(frame, input)
          assert normalized.source_epoch == frame.source_epoch
          normalized
        end
      else
        assert {:ok, normalizer} = IncomingAudio.new_normalizer(example, target)

        fn frame ->
          assert {:ok, normalized} = IncomingAudio.speech_frame(frame, normalizer)
          assert normalized.source_epoch == frame.source_epoch
          normalized
        end
      end

    {normalize, source}
  end

  defp source_frame(:webrtc, rate, channels, payload, index, receipt, epoch) do
    session = %Snapshot{
      session_id: "session",
      tenant_id: "tenant",
      actor_id: "actor",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      tool_visibility: ToolVisibility.hidden(),
      expires_at: ~U[2026-11-19 23:00:00Z]
    }

    codec = %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: rate,
      channels: channels
    }

    packet = %Packet{
      payload_type: 111,
      sequence_number: index + 1,
      timestamp: index * div(rate, 50),
      ssrc: 123,
      payload: payload
    }

    assert {:ok, frame} =
             RTPFrame.from_rtp(session, "connection", "track", codec, packet, receipt)

    %{frame | source_epoch: epoch}
  end

  defp source_frame(:carrier, rate, channels, payload, index, receipt, epoch) do
    %AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      connection_id: "connection",
      track_id: "track",
      codec: :opus,
      sample_rate: rate,
      channels: channels,
      sequence_number: index + 1,
      timestamp: index * div(rate, 50),
      payload: payload,
      received_at: receipt,
      source_epoch: epoch
    }
  end
end
