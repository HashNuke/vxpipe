defmodule Vxpipe.Gateway.Media.STSInputTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{ConnectionAttachment, STSInputHandle}
  alias Vxpipe.CallEngine.Media.{AudioFrame, STSIngress}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.Gateway.Media.STSInput
  alias Vxpipe.Gateway.WebRTC.Connection
  alias Vxpipe.Gateway.Telephony.{MediaBinding, MediaSession}
  alias Vxpipe.Providers.Twilio.PCMU.Codec

  test "WebRTC prepares STS without human STT and unwraps RTP sequence numbers" do
    {attachment, ingress, identity} = input()
    track = %{track_id: "microphone", codec: :opus, sample_rate: 48_000, channels: 2}
    assert {:ok, output, prepared} = STSInput.prepare(attachment, track, nil, :webrtc)
    assert output == %{track | codec: :linear16, sample_rate: 16_000, channels: 1}
    assert {:ok, ^output, ^prepared} = STSInput.prepare(attachment, track, prepared, :webrtc)
    assert :ok = STSIngress.open(ingress)
    encoder = Membrane.Opus.Encoder.Native.create(48_000, 2, 2_048, 64_000, 3_001)
    pcm = :binary.copy(<<1_000::little-signed-16, -500::little-signed-16>>, 960)
    assert {:ok, payload} = Membrane.Opus.Encoder.Native.encode_packet(encoder, pcm, 960)
    frame = frame(identity, track, payload, 65_535)
    assert {:ok, prepared} = STSInput.push(attachment, frame, prepared)
    assert_receive {:vxpipe_sts_input, ^ingress, ref, converted, 0}
    assert converted.sequence_number == 65_535
    assert converted.sample_rate == 16_000
    assert converted.channels == 1
    assert converted.timestamp == 320
    assert byte_size(converted.payload) == 640
    ack(ingress, ref)

    assert {:ok, prepared} = STSInput.push(attachment, %{frame | sequence_number: 0}, prepared)
    assert_receive {:vxpipe_sts_input, ^ingress, ref, %{sequence_number: 65_536}, 0}
    ack(ingress, ref)
    assert {{:error, :stale_sequence}, ^prepared} = STSInput.push(attachment, frame, prepared)
    refute_received {:vxpipe_sts_input, _, _, _, _}
  end

  test "Twilio PCMU reaches its own STS input as 16 kHz mono PCM" do
    {attachment, ingress, identity} = input()
    track = %{track_id: "microphone", codec: :pcmu, sample_rate: 8_000, channels: 1}
    assert {:ok, output, prepared} = STSInput.prepare(attachment, track, nil, :telephony)
    assert output == %{track | codec: :linear16, sample_rate: 16_000}
    assert :ok = STSIngress.open(ingress)
    assert {:ok, payload} = Codec.encode(:binary.copy(<<1_000::little-signed-16>>, 160))

    assert {:ok, _prepared} =
             STSInput.push(attachment, frame(identity, track, payload, 1), prepared)

    assert_receive {:vxpipe_sts_input, ^ingress, _, converted, 0}
    assert converted.codec == :linear16
    assert converted.sample_rate == 16_000
    assert converted.timestamp == 1_920
    assert byte_size(converted.payload) == 640
  end

  test "Telnyx Opus keeps an independent mono decoder for STS" do
    {attachment, ingress, identity} = input()
    track = %{track_id: "microphone", codec: :opus, sample_rate: 16_000, channels: 1}
    assert {:ok, _output, prepared} = STSInput.prepare(attachment, track, nil, :telephony)
    assert :ok = STSIngress.open(ingress)
    encoder = Membrane.Opus.Encoder.Native.create(16_000, 1, 2_048, -1_000, 3_001)
    pcm = :binary.copy(<<1_000::little-signed-16>>, 320)
    assert {:ok, payload} = Membrane.Opus.Encoder.Native.encode_packet(encoder, pcm, 320)

    assert {:ok, _prepared} =
             STSInput.push(attachment, frame(identity, track, payload, 1), prepared)

    assert_receive {:vxpipe_sts_input, ^ingress, _, converted, 0}
    assert converted.codec == :linear16
    assert converted.sample_rate == 16_000
    assert converted.timestamp == 960
    assert byte_size(converted.payload) == 640
  end

  test "unsupported conversion and missing STS allocation fail preparation explicitly" do
    {attachment, _ingress, _identity} = input(44_100)
    track = %{track_id: "microphone", codec: :opus, sample_rate: 48_000, channels: 1}
    assert {:error, :unsupported_audio} = STSInput.prepare(attachment, track, nil, :webrtc)

    assert {:error, :speech_to_speech_unavailable} =
             STSInput.prepare(%{attachment | speech_to_speech_input: nil}, track, nil, :webrtc)
  end

  test "WebRTC connection prepares and forwards STS-only microphone input" do
    {attachment, ingress, identity} = input()
    track = %{track_id: "microphone", codec: :opus, sample_rate: 48_000, channels: 2}

    codec = %ExWebRTC.RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }

    state = %{
      attachment: attachment,
      speech_input: nil,
      sts_input: nil,
      peer_connection: self(),
      audio_tracks: %{"microphone" => %{111 => codec}},
      room_audio_ingress: nil,
      session:
        struct!(
          Vxpipe.Gateway.Session.Snapshot,
          Map.merge(
            Map.delete(identity, :connection_id),
            %{
              session_id: "session",
              actor_id: "actor",
              expires_at: DateTime.utc_now(),
              tool_visibility: Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility.hidden()
            }
          )
        ),
      connection_id: identity.connection_id
    }

    assert {:reply, {:ok, %{codec: :linear16}}, state} =
             Connection.handle_call({:speech_to_speech_track, track}, {self(), make_ref()}, state)

    assert :ok = STSIngress.open(ingress)
    encoder = Membrane.Opus.Encoder.Native.create(48_000, 2, 2_048, 64_000, 3_001)
    pcm = :binary.copy(<<1_000::little-signed-16, -500::little-signed-16>>, 960)
    assert {:ok, payload} = Membrane.Opus.Encoder.Native.encode_packet(encoder, pcm, 960)

    packet = %ExRTP.Packet{
      payload_type: 111,
      sequence_number: 65_535,
      timestamp: 960,
      ssrc: 123,
      payload: payload
    }

    assert {:noreply, state} =
             Connection.handle_info(
               {:ex_webrtc, self(), {:rtp, "microphone", nil, packet}},
               state
             )

    assert_receive {:vxpipe_sts_input, ^ingress, ref, %{sequence_number: 65_535}, 0}
    ack(ingress, ref)

    assert {:noreply, _state} =
             Connection.handle_info(
               {:ex_webrtc, self(), {:rtp, "microphone", nil, %{packet | sequence_number: 0}}},
               state
             )

    assert_receive {:vxpipe_sts_input, ^ingress, ref, %{sequence_number: 65_536}, 0}
    ack(ingress, ref)
  end

  test "telephony session keeps STS-only delivery live across policy denial" do
    {attachment, ingress, identity} = input()
    track = %{track_id: "microphone", codec: :pcmu, sample_rate: 8_000, channels: 1}

    binding =
      struct!(
        MediaBinding,
        Map.merge(identity, %{
          provider: :twilio,
          service_id: "test",
          ingress_key: "test",
          call_id: "call",
          provider_connection_id: "provider-connection",
          provider_call_control_id: "control",
          provider_call_leg_id: "leg",
          provider_call_session_id: nil,
          client_state_leg_id: identity.connection_id,
          leg: self()
        })
        |> Map.delete(:connection_id)
      )

    state = %{
      attachment: attachment,
      binding: binding,
      speech_normalizer: nil,
      sts_input: nil,
      room_audio_ingress: nil,
      engine: Vxpipe.CallEngine,
      socket_owner: self(),
      stream_id: "microphone"
    }

    assert {:reply, {:ok, %{codec: :linear16}}, state} =
             MediaSession.handle_call(
               {:speech_to_speech_track, track},
               {self(), make_ref()},
               state
             )

    assert :ok = STSIngress.open(ingress)
    assert {:ok, payload} = Codec.encode(:binary.copy(<<1_000::little-signed-16>>, 160))

    event =
      struct!(Vxpipe.CallEngine.Telephony.Event, %{
        kind: :media,
        stream_id: "microphone",
        provider: :twilio,
        provider_call_control_id: "control",
        media: %Vxpipe.CallEngine.Telephony.MediaPacket{
          codec: :pcmu,
          sample_rate: 8_000,
          channels: 1,
          sequence_number: 1,
          timestamp: 160,
          payload: payload
        }
      })

    assert {:reply, :ok, state} = MediaSession.handle_call({:event, self(), event}, nil, state)
    assert_receive {:vxpipe_sts_input, ^ingress, ref, %{sample_rate: 16_000}, 0}
    ack(ingress, ref)

    denied = %Snapshot{
      revision: 1,
      present_participant_ids: MapSet.new(["caller", "agent"]),
      effective: %Effective{
        audio_routes: %{},
        transcript_routes: :unrestricted,
        record_audio: false,
        save_transcripts: false
      }
    }

    assert :ok = Enforcer.apply(ingress, denied, 500)
    event = %{event | media: %{event.media | sequence_number: 2}}
    assert {:reply, :ok, state} = MediaSession.handle_call({:event, self(), event}, nil, state)
    refute_received {:vxpipe_sts_input, _, _, _, _}

    assert :ok =
             Enforcer.apply(
               ingress,
               %{
                 denied
                 | revision: 2,
                   effective: %{denied.effective | audio_routes: :unrestricted}
               },
               500
             )

    event = %{event | media: %{event.media | sequence_number: 3}}
    assert {:reply, :ok, _state} = MediaSession.handle_call({:event, self(), event}, nil, state)
    assert_receive {:vxpipe_sts_input, ^ingress, ref, %{sequence_number: 3}, 2}
    ack(ingress, ref)
  end

  test "STS candidate handoff is explicitly unsupported before any media preparation" do
    assert {:error, :unsupported_sts_handoff} =
             Vxpipe.Gateway.Media.ConnectionReadiness.prepare_candidate(
               %{},
               %{},
               %{speech_to_speech?: true},
               []
             )
  end

  for transport <- [:webrtc, :telephony], blocked <- [:stt, :sts] do
    test "#{transport} continues the other input when #{blocked} exhausts its delivery credit" do
      {attachment, sts, identity} = input(16_000, maximum_frames: 1)

      stt =
        start_supervised!(
          {Vxpipe.CallEngine.Media.Ingress,
           Map.to_list(identity) ++
             [
               capability: self(),
               maximum_age_ms: 1_000,
               maximum_bytes: 4_096,
               maximum_frames: 1,
               maximum_consecutive_overflows: 3
             ]}
        )

      attachment = %{attachment | media_ingress: stt}
      {track, payload} = source_audio(unquote(transport))

      assert {:ok, _output, prepared} =
               STSInput.prepare(attachment, track, nil, unquote(transport))

      assert :ok = STSIngress.open(sts)
      deliver = delivery(unquote(transport), attachment, identity, track, payload)
      assert {:ok, prepared} = deliver.(1, prepared)
      assert_receive {:vxpipe_sts_input, ^sts, sts_ref, %{sequence_number: 1}, 0}
      assert_receive {:vxpipe_stt_audio, ^stt, stt_ref, %{sequence_number: 1}}

      case unquote(blocked) do
        :stt ->
          ack(sts, sts_ref)
          assert {:ok, _prepared} = deliver.(2, prepared)
          assert_receive {:vxpipe_sts_input, ^sts, sts_ref, %{sequence_number: 2}, 0}
          ack(sts, sts_ref)
          refute_received {:vxpipe_stt_audio, ^stt, _, %{sequence_number: 2}}

        :sts ->
          send(stt, {:vxpipe_stt_audio_result, self(), stt_ref, 1, :ok})
          _ = :sys.get_state(stt)
          assert {:ok, _prepared} = deliver.(2, prepared)
          assert_receive {:vxpipe_stt_audio, ^stt, _, %{sequence_number: 2}}
          assert %{dropped: 1, in_flight?: true} = STSIngress.stats(sts)
          ack(sts, sts_ref)
          refute_received {:vxpipe_sts_input, ^sts, _, %{sequence_number: 2}, _}
      end
    end
  end

  defp delivery(:telephony, attachment, identity, track, payload) do
    fn sequence, input ->
      Vxpipe.Gateway.Telephony.IncomingAudio.deliver(
        Vxpipe.CallEngine,
        attachment,
        nil,
        frame(identity, track, payload, sequence),
        :pcmu_to_pcm16,
        input
      )
    end
  end

  defp delivery(:webrtc, attachment, identity, track, payload) do
    assert {:ok, _output, speech_input} =
             Vxpipe.Gateway.WebRTC.SpeechInput.configure(
               track,
               %{codec: :linear16, sample_rate: 16_000, channels: 1}
             )

    codec = %ExWebRTC.RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }

    session =
      struct!(
        Vxpipe.Gateway.Session.Snapshot,
        Map.merge(
          Map.delete(identity, :connection_id),
          %{
            session_id: "session",
            actor_id: "actor",
            expires_at: DateTime.utc_now(),
            tool_visibility: Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility.hidden()
          }
        )
      )

    fn sequence, input ->
      packet = %ExRTP.Packet{
        payload_type: 111,
        sequence_number: sequence,
        timestamp: 960,
        ssrc: 123,
        payload: payload
      }

      Vxpipe.Gateway.WebRTC.IncomingAudio.forward(codec, track.track_id, packet,
        session: session,
        connection_id: identity.connection_id,
        attachment: attachment,
        speech_input: speech_input,
        sts_input: input,
        received_at: System.monotonic_time(:millisecond)
      )
    end
  end

  defp source_audio(:webrtc) do
    encoder = Membrane.Opus.Encoder.Native.create(48_000, 2, 2_048, 64_000, 3_001)
    pcm = :binary.copy(<<1_000::little-signed-16, -500::little-signed-16>>, 960)
    assert {:ok, payload} = Membrane.Opus.Encoder.Native.encode_packet(encoder, pcm, 960)
    {%{track_id: "microphone", codec: :opus, sample_rate: 48_000, channels: 2}, payload}
  end

  defp source_audio(:telephony) do
    assert {:ok, payload} = Codec.encode(:binary.copy(<<1_000::little-signed-16>>, 160))
    {%{track_id: "microphone", codec: :pcmu, sample_rate: 8_000, channels: 1}, payload}
  end

  defp input(rate \\ 16_000, limits \\ []) do
    identity = %{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "caller",
      connection_id: "connection-#{System.unique_integer([:positive])}"
    }

    handle = STSInputHandle.new(identity, self())

    ingress =
      start_supervised!(
        {STSIngress,
         [
           name: STSInputHandle.address(handle),
           source_connection: self(),
           capability: self(),
           identity: identity,
           agent_id: "agent",
           format: %{codec: :linear16, sample_rate: rate, channels: 1}
         ] ++ limits}
      )

    policy = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["caller", "agent"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: false,
        save_transcripts: false
      }
    }

    assert :ok = Enforcer.apply(ingress, policy, 500)

    attachment = %ConnectionAttachment{
      room_monitor: make_ref(),
      media_ingress: nil,
      connection: self(),
      speech_to_speech_input: handle,
      room_audio_input_mode: :enabled
    }

    {attachment, ingress, identity}
  end

  defp frame(identity, track, payload, sequence) do
    struct!(
      AudioFrame,
      Map.merge(
        identity,
        Map.merge(track, %{
          payload: payload,
          sequence_number: sequence,
          timestamp: 960,
          received_at: System.monotonic_time(:millisecond)
        })
      )
    )
  end

  defp ack(ingress, ref) do
    send(ingress, {:vxpipe_sts_input_result, self(), ref, :ok})
    assert %{in_flight?: false} = STSIngress.stats(ingress)
  end
end
