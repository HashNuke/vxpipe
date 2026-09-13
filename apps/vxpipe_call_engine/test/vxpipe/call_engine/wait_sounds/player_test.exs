defmodule Vxpipe.CallEngine.WaitSounds.PlayerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.OpeningAudio.Asset
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.WaitSounds.Player

  test "listeners share a ten-second asset but pause at seven and three seconds independently" do
    asset = asset(for i <- 0..499, into: <<>>, do: :binary.copy(<<i::little-signed-16>>, 960))
    {first, first_sink} = start_player(asset, "first")
    {second, second_sink} = start_player(asset, "second")
    advance(first_sink, 349)
    advance(second_sink, 149)
    pause_after_frame(first, first_sink)
    assert_receive {:vxpipe_wait_playback, ^first, "first", {:paused, 336_000}}
    pause_after_frame(second, second_sink)
    assert_receive {:vxpipe_wait_playback, ^second, "second", {:paused, 144_000}}

    Player.resume(first)
    assert_receive {:test_audio_output, ^first_sink, frame}
    assert frame.payload == :binary.copy(<<350::little-signed-16>>, 960)
    refute_receive {:test_audio_output, ^second_sink, _frame}
    Player.resume(second)
    assert_receive {:test_audio_output, ^second_sink, frame}
    assert frame.payload == :binary.copy(<<150::little-signed-16>>, 960)
  end

  test "waits for real completion on every sink and loops without adding a boundary gap" do
    pcm = <<1::little-signed-16, 2::little-signed-16, 3::little-signed-16>>
    {player, sink} = start_player(asset(pcm), "loop")
    assert_receive {:test_audio_output, ^sink, frame}
    assert frame.payload == :binary.copy(pcm, 320)
    assert frame.audio_scope == :private
    assert_receive {:test_audio_output_finish, ^sink, correlation}
    assert :ok = TestAudioOutputSink.playback_started(sink)
    assert :ok = TestAudioOutputSink.playback_progress(sink, 10, 20)
    send(player, {:vxpipe_audio_playback, sink, "stale", {:completed, 20}})
    refute_receive {:test_audio_output, ^sink, _frame}
    complete(sink)
    assert_receive {:test_audio_output, ^sink, next}
    assert next.payload == frame.payload
    refute next.correlation_id == correlation
  end

  test "finite cue completion and stop wait for the final acknowledged frame" do
    {player, sink} =
      start_player(asset(:binary.copy(<<10::little-signed-16>>, 1_200)), "cue", loop: false)

    assert_receive {:test_audio_output, ^sink, first}
    assert byte_size(first.payload) == 1_920
    assert_receive {:test_audio_output_finish, ^sink, _}
    monitor = Process.monitor(player)
    complete(sink)
    assert_receive {:test_audio_output, ^sink, last}
    assert byte_size(last.payload) == 480
    assert_receive {:test_audio_output_finish, ^sink, _}
    refute_receive {:vxpipe_wait_playback, ^player, "cue", :completed}
    complete(sink)
    assert_receive {:vxpipe_wait_playback, ^player, "cue", :completed}
    assert_receive {:DOWN, ^monitor, :process, ^player, :normal}
  end

  test "a failed output ends only its player and reports failure" do
    {first, first_sink} = start_player(asset(<<1::little-signed-16>>), "first")
    {_second, second_sink} = start_player(asset(<<2::little-signed-16>>), "second")
    assert_receive {:test_audio_output_finish, ^first_sink, _}
    monitor = Process.monitor(first)
    Process.exit(first_sink, :kill)
    assert_receive {:vxpipe_wait_playback, ^first, "first", {:failed, :output_unavailable}}
    assert_receive {:DOWN, ^monitor, :process, ^first, :normal}
    advance(second_sink, 1)
    assert_receive {:test_audio_output, ^second_sink, _}
  end

  test "multiple output sinks follow one participant cursor and stop only after both drain" do
    second_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())

    {player, first_sink} =
      start_player(asset(:binary.copy(<<4::little-signed-16>>, 960)), "shared",
        extra_sink: second_sink
      )

    assert_receive {:test_audio_output, ^first_sink, first}
    assert_receive {:test_audio_output, ^second_sink, second}
    assert first.payload == second.payload
    assert first.correlation_id == second.correlation_id
    assert_receive {:test_audio_output_finish, ^first_sink, _}
    assert_receive {:test_audio_output_finish, ^second_sink, _}
    Player.stop(player)
    _ = :sys.get_state(player)
    monitor = Process.monitor(player)
    complete(first_sink)
    refute_receive {:vxpipe_wait_playback, ^player, "shared", :stopped}
    refute_receive {:test_audio_output, _, _}
    complete(second_sink)
    assert_receive {:vxpipe_wait_playback, ^player, "shared", :stopped}
    assert_receive {:DOWN, ^monitor, :process, ^player, :normal}
  end

  defp start_player(asset, episode, options \\ []) do
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())

    sinks =
      case Keyword.get(options, :extra_sink) do
        nil -> %{"connection-#{episode}" => sink}
        extra -> %{"connection-#{episode}" => sink, "extra-#{episode}" => extra}
      end

    player =
      start_supervised!(
        {Player,
         [
           asset: asset,
           owner: self(),
           episode_id: episode,
           tenant_id: "tenant",
           room_id: "room",
           incarnation_id: "incarnation",
           participant_id: episode,
           connection_generation: 1,
           attempt_id: "attempt",
           phase: :transfer,
           sinks: sinks
         ] ++ options},
        id: make_ref()
      )

    {player, sink}
  end

  defp advance(_sink, 0), do: :ok

  defp advance(sink, frames) do
    for _ <- 1..frames do
      assert_receive {:test_audio_output, ^sink, _}
      assert_receive {:test_audio_output_finish, ^sink, _}
      complete(sink)
    end
  end

  defp pause_after_frame(player, sink) do
    assert_receive {:test_audio_output, ^sink, _}
    assert_receive {:test_audio_output_finish, ^sink, _}
    Player.pause(player)
    _ = :sys.get_state(player)
    complete(sink)
  end

  defp complete(sink) do
    :ok = TestAudioOutputSink.playback_progress(sink, 20, 20)
    :ok = TestAudioOutputSink.playback_completed(sink)
  end

  defp asset(payload) do
    %Asset{
      codec: :linear16,
      sample_rate: 48_000,
      channels: 1,
      byte_order: :little,
      duration_ms: div(byte_size(payload), 96),
      payload: payload
    }
  end
end
