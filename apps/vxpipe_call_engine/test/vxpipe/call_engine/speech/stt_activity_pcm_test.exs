defmodule Vxpipe.CallEngine.Speech.STTActivityPCMTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Speech.STTActivityPCM

  test "normalizes detector branch by sample timestamp without altering recognition bytes" do
    frame = frame(:linear16, 48_000, :binary.copy(<<20, 0>>, 960), 960)
    assert {:ok, pcm, 320} = STTActivityPCM.normalize(frame)
    assert pcm == :binary.copy(<<20, 0>>, 320)
    assert byte_size(frame.payload) == 1_920
    next = %{frame | timestamp: 1_920}
    assert {:ok, ^pcm, 640} = STTActivityPCM.normalize(next)
  end

  test "Opus uses mono PCM supplied by the owning decoder at the exact frame timestamp" do
    frame = frame(:opus, 48_000, <<1, 2, 3>>, 960)
    pcm = :binary.copy(<<5, 0>>, 960)
    decoded = %{payload: pcm, sample_rate: 48_000, channels: 1, timestamp: 960}

    assert {:ok, normalized, 320} =
             STTActivityPCM.normalize(Map.put(frame, :activity_pcm, decoded))

    assert normalized == :binary.copy(<<5, 0>>, 320)
    assert {:error, :unsupported_audio} = STTActivityPCM.normalize(frame)

    for invalid <- [
          %{decoded | timestamp: 961},
          %{decoded | channels: 2},
          %{decoded | sample_rate: 16_000},
          %{decoded | payload: <<1>>},
          Map.put(decoded, :extra, :bad),
          %{decoded | payload: :binary.copy(<<0>>, 131_072)}
        ] do
      assert {:error, :unsupported_audio} =
               STTActivityPCM.normalize(Map.put(frame, :activity_pcm, invalid))
    end
  end

  test "supports recognizer PCM rates while bounding normalization before expansion" do
    for rate <- [32_000, 44_100] do
      pcm = :binary.copy(<<20, 0>>, div(rate, 50))
      assert {:ok, normalized, 0} = STTActivityPCM.normalize(frame(:linear16, rate, pcm, 0))
      assert byte_size(normalized) in 640..642
    end

    assert {:error, :unsupported_audio} =
             STTActivityPCM.normalize(frame(:linear16, 1, :binary.copy(<<0>>, 100), 0))
  end

  defp frame(codec, rate, payload, timestamp) do
    struct!(AudioFrame,
      tenant_id: "t",
      room_id: "r",
      incarnation_id: "i",
      participant_id: "p",
      connection_id: "c",
      track_id: "a",
      codec: codec,
      sample_rate: rate,
      channels: 1,
      sequence_number: 1,
      timestamp: timestamp,
      payload: payload,
      received_at: 1
    )
  end
end
