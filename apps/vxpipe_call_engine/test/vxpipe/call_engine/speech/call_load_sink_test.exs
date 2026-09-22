defmodule Vxpipe.CallEngine.Speech.CallLoadSinkTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallLoad.Sink
  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, OutputSink}

  test "interruption and clear fence exact old finish tokens without scheduler timing assumptions" do
    clock = start_supervised!({Agent, fn -> 1_000 end})
    observer = self()

    sink =
      start_supervised!(
        {Sink,
         observer: observer,
         clock: fn -> Agent.get(clock, & &1) end,
         schedule_finish: fn message, delay -> send(observer, {:scheduled, message, delay}) end}
      )

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
    assert_received {:scheduled, {:finish, old_token}, 200}
    assert_received {:vxpipe_audio_playback, ^sink, "turn", :started}
    Agent.update(clock, fn _ -> 1_030 end)
    assert {:ok, 30} = OutputSink.interrupt(sink, "turn", self())
    send(sink, {:finish, old_token})
    _ = :sys.get_state(sink)
    refute_received {:vxpipe_audio_playback, ^sink, "turn", {:completed, _}}
    assert %{interrupted_chunks: chunks} = Sink.stats(sink)
    assert chunks > 0

    assert :ok = OutputSink.push(sink, %{frame | correlation_id: "cleared"})
    assert :ok = OutputSink.finish(sink, "cleared", self())
    assert_received {:scheduled, {:finish, clear_token}, 200}
    send(sink, {:finish, old_token})
    _ = :sys.get_state(sink)
    refute_received {:vxpipe_audio_playback, ^sink, _, {:completed, _}}
    Agent.update(clock, fn _ -> 1_060 end)
    assert {:ok, 30} = OutputSink.clear(sink)
    send(sink, {:finish, clear_token})
    _ = :sys.get_state(sink)
    refute_received {:vxpipe_audio_playback, ^sink, _, {:completed, _}}

    assert :ok = OutputSink.push(sink, %{frame | correlation_id: "current"})
    assert :ok = OutputSink.finish(sink, "current", self())
    assert_received {:scheduled, {:finish, current_token}, 200}
    Agent.update(clock, fn _ -> 1_260 end)
    send(sink, {:finish, current_token})
    _ = :sys.get_state(sink)
    assert_received {:vxpipe_audio_playback, ^sink, "current", {:completed, 200}}
  end
end
