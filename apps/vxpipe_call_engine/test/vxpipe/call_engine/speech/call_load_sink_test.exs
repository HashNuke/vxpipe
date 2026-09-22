defmodule Vxpipe.CallEngine.Speech.CallLoadSinkTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallLoad.Sink
  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, OutputSink}

  test "finish acknowledges elapsed PCM consumption and interruption fences old completion" do
    sink = start_supervised!({Sink, observer: self()})

    frame =
      struct!(
        AudioOutputFrame,
        Map.merge(Map.from_struct(AudioOutputFrame.__struct__()), %{
          correlation_id: "turn",
          reply_to: self(),
          payload: :binary.copy(<<0>>, 6_400),
          codec: :linear16,
          sample_rate: 16_000,
          channels: 1
        })
        |> Map.delete(:__struct__)
      )

    assert :ok = OutputSink.push(sink, frame)
    assert :ok = OutputSink.finish(sink, "turn", self())
    assert_receive {:vxpipe_audio_playback, ^sink, "turn", :started}
    refute_receive {:vxpipe_audio_playback, ^sink, "turn", {:completed, _}}, 30
    assert {:ok, played} = OutputSink.interrupt(sink, "turn", self())
    assert played >= 30 and played < 200
    refute_receive {:vxpipe_audio_playback, ^sink, "turn", {:completed, _}}, 220
    assert %{interrupted_chunks: chunks} = Sink.stats(sink)
    assert chunks > 0

    assert :ok = OutputSink.push(sink, %{frame | correlation_id: "cleared"})
    assert :ok = OutputSink.finish(sink, "cleared", self())
    refute_receive {:vxpipe_audio_playback, ^sink, "cleared", {:completed, _}}, 30
    assert {:ok, cleared_ms} = OutputSink.clear(sink)
    assert cleared_ms >= 30 and cleared_ms < 200
    refute_receive {:vxpipe_audio_playback, ^sink, "cleared", {:completed, _}}, 220
  end
end
