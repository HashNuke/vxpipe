defmodule Vxpipe.Gateway.WebRTC.NegotiatedAudioTest do
  use ExUnit.Case, async: true

  alias ExSDP.Attribute.FMTP
  alias ExWebRTC.{MediaStreamTrack, RTPCodecParameters, RTPReceiver, RTPSender, RTPTransceiver}
  alias Vxpipe.Gateway.WebRTC.NegotiatedAudio

  test "requires negotiated direction and a compatible codec for the exact output track" do
    transceiver = transceiver()
    track = transceiver.sender.track.id

    assert {:preparing, nil} =
             NegotiatedAudio.resolve(:output, [%{transceiver | current_direction: nil}], track)

    assert {:preparing, nil} = NegotiatedAudio.resolve(:output, [transceiver], :another_track)
    assert {:ready, output} = NegotiatedAudio.resolve(:output, [transceiver], track)
    assert output.track.codec == :opus
    assert {:ready, input} = NegotiatedAudio.resolve(:input, [transceiver], track)
    assert input.track.track_id == to_string(transceiver.receiver.track.id)
    assert input.track.sample_rate == 48_000
    assert input.track.channels == 2

    pcmu = %RTPCodecParameters{
      mime_type: "audio/PCMU",
      payload_type: 0,
      clock_rate: 8_000,
      channels: 1
    }

    incompatible = %{transceiver | sender: %{transceiver.sender | codec: pcmu}, codecs: [pcmu]}
    assert {:failed, nil} = NegotiatedAudio.resolve(:output, [incompatible], track)
    assert {:failed, nil} = NegotiatedAudio.resolve(:input, [incompatible], track)
  end

  test "does not treat an FMTP stereo preference as incoming channel evidence" do
    transceiver = transceiver()

    stereo = %{
      hd(transceiver.codecs)
      | sdp_fmtp_line: %FMTP{pt: 111, stereo: true}
    }

    transceiver = %{transceiver | codecs: [stereo]}

    assert {:ready, input} =
             NegotiatedAudio.resolve(:input, [transceiver], transceiver.sender.track.id)

    assert input.track.channels == 2
  end

  test "does not pick an arbitrary input when multiple active tracks are negotiated" do
    first = transceiver()
    second = transceiver()

    assert {:failed, nil} =
             NegotiatedAudio.resolve(:input, [first, second], first.sender.track.id)

    assert {:ready, input} = NegotiatedAudio.resolve(:input, [first], first.sender.track.id)

    assert {:ready, ^input} =
             NegotiatedAudio.resolve(
               :input,
               [first, %{second | stopped: true}],
               first.sender.track.id
             )

    assert {:preparing, nil} =
             NegotiatedAudio.resolve(
               :input,
               [%{first | current_direction: :sendonly}],
               first.sender.track.id
             )
  end

  test "retains the unchanged direction's binding when the other direction changes" do
    transceiver = transceiver()
    output_track = transceiver.sender.track.id
    assert {:ready, output} = NegotiatedAudio.resolve(:output, [transceiver], output_track)
    assert {:ready, input} = NegotiatedAudio.resolve(:input, [transceiver], output_track)

    assert {:ready, ^output} =
             NegotiatedAudio.resolve(
               :output,
               [%{transceiver | current_direction: :sendonly}],
               output_track
             )

    assert {:ready, ^input} =
             NegotiatedAudio.resolve(
               :input,
               [%{transceiver | current_direction: :recvonly}],
               output_track
             )
  end

  defp transceiver do
    opus = %RTPCodecParameters{
      mime_type: "audio/opus",
      payload_type: 111,
      clock_rate: 48_000,
      channels: 2
    }

    %RTPTransceiver{
      id: System.unique_integer([:positive]),
      kind: :audio,
      mid: "0",
      direction: :sendrecv,
      current_direction: :sendrecv,
      stopping: false,
      stopped: false,
      header_extensions: [],
      codecs: [opus],
      sender: %RTPSender{id: 1, track: MediaStreamTrack.new(:audio), codec: opus},
      receiver: %RTPReceiver{id: 2, track: MediaStreamTrack.new(:audio), codec: opus}
    }
  end
end
