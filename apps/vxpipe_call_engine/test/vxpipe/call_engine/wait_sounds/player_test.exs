defmodule Vxpipe.CallEngine.WaitSounds.PlayerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.OpeningAudio.Asset
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.WaitSounds.Player

  # A frame-by-frame player waited for each 20 ms frame to finish playing before sending the
  # next, so every round trip became a gap in the caller's audio and a 250 ms cue took up to a
  # second on a busy server. The sink must always hold the next frames already.
  test "keeps a window of frames queued in one turn instead of waiting for each frame to play" do
    pcm = for i <- 0..49, into: <<>>, do: :binary.copy(<<i::little-signed-16>>, 960)
    {_player, sink} = start_player(asset(pcm), "window")

    frames =
      for index <- 0..4 do
        assert_receive {:test_audio_output, ^sink, frame}
        assert frame.payload == :binary.copy(<<index::little-signed-16>>, 960)
        frame
      end

    assert frames |> Enum.map(& &1.correlation_id) |> Enum.uniq() |> length() == 1
    refute_received {:test_audio_output_finish, ^sink, _}
  end

  test "pausing interrupts the sinks and resumes from the exact played frame" do
    pcm = for i <- 0..49, into: <<>>, do: :binary.copy(<<i::little-signed-16>>, 960)
    {player, sink} = start_player(asset(pcm), "exact-pause")
    assert_receive {:test_audio_output, ^sink, _first}
    assert :ok = TestAudioOutputSink.playback_progress(sink, 60, 60)

    Player.pause(player)
    assert_receive {:test_audio_output_interrupt, ^sink, _turn, 60}
    assert_receive {:vxpipe_wait_playback, ^player, "exact-pause", {:paused, 2_880}}
    flush_outputs(sink)

    Player.resume(player)
    assert_receive {:test_audio_output, ^sink, resumed}
    assert resumed.payload == :binary.copy(<<3::little-signed-16>>, 960)
  end

  test "a cue streams in one turn, finishes once and completes after playback and drain" do
    pcm = :binary.copy(<<10::little-signed-16>>, 1_200)
    {player, sink} = start_player(asset(pcm), "streamed-cue", loop: false)
    assert_receive {:test_audio_output, ^sink, first}
    assert_receive {:test_audio_output, ^sink, last}
    assert {byte_size(first.payload), byte_size(last.payload)} == {1_920, 480}
    assert first.correlation_id == last.correlation_id
    assert_receive {:test_audio_output_finish, ^sink, turn}
    assert turn == first.correlation_id
    refute_received {:vxpipe_wait_playback, ^player, "streamed-cue", :completed}

    monitor = Process.monitor(player)
    assert :ok = TestAudioOutputSink.playback_progress(sink, 25, 25)
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_wait_playback, ^player, "streamed-cue", :completed}
    assert_receive {:DOWN, ^monitor, :process, ^player, :normal}
  end

  test "stop interrupts playback at once and reports stopped" do
    pcm = for i <- 0..49, into: <<>>, do: :binary.copy(<<i::little-signed-16>>, 960)
    {player, sink} = start_player(asset(pcm), "prompt-stop")
    assert_receive {:test_audio_output, ^sink, _first}
    monitor = Process.monitor(player)
    Player.stop(player)
    assert_receive {:test_audio_output_interrupt, ^sink, _turn, _played}
    assert_receive {:vxpipe_wait_playback, ^player, "prompt-stop", :stopped}
    assert_receive {:DOWN, ^monitor, :process, ^player, :normal}
  end

  test "listeners share a ten-second asset but pause at seven and three seconds independently" do
    asset = asset(for i <- 0..499, into: <<>>, do: :binary.copy(<<i::little-signed-16>>, 960))
    {first, first_sink} = start_player(asset, "first")
    {second, second_sink} = start_player(asset, "second")
    assert_receive {:test_audio_output, ^first_sink, _}
    assert_receive {:test_audio_output, ^second_sink, _}
    assert :ok = TestAudioOutputSink.playback_progress(first_sink, 7_000, 7_000)
    assert :ok = TestAudioOutputSink.playback_progress(second_sink, 3_000, 3_000)
    Player.pause(first)
    assert_receive {:vxpipe_wait_playback, ^first, "first", {:paused, 336_000}}
    Player.pause(second)
    assert_receive {:vxpipe_wait_playback, ^second, "second", {:paused, 144_000}}
    flush_outputs(first_sink)
    flush_outputs(second_sink)

    Player.resume(first)
    assert_receive {:test_audio_output, ^first_sink, frame}
    assert frame.payload == :binary.copy(<<350::little-signed-16>>, 960)
    refute_receive {:test_audio_output, ^second_sink, _frame}
    Player.resume(second)
    assert_receive {:test_audio_output, ^second_sink, frame}
    assert frame.payload == :binary.copy(<<150::little-signed-16>>, 960)
  end

  test "loops a short asset seamlessly within one turn and ignores stale completions" do
    pcm = <<1::little-signed-16, 2::little-signed-16, 3::little-signed-16>>
    {player, sink} = start_player(asset(pcm), "loop")
    assert_receive {:test_audio_output, ^sink, frame}
    assert frame.payload == :binary.copy(pcm, 320)
    assert frame.audio_scope == :private
    send(player, {:vxpipe_audio_playback, sink, "stale", {:completed, 20}})
    assert_receive {:test_audio_output, ^sink, next}
    assert next.payload == frame.payload
    assert next.correlation_id == frame.correlation_id
    refute_received {:test_audio_output_finish, ^sink, _}
  end

  test "a failed output ends only its player and reports failure" do
    {first, first_sink} = start_player(asset(<<1::little-signed-16>>), "first")
    {_second, second_sink} = start_player(asset(<<2::little-signed-16>>), "second")
    assert_receive {:test_audio_output, ^first_sink, _}
    monitor = Process.monitor(first)
    Process.exit(first_sink, :kill)
    assert_receive {:vxpipe_wait_playback, ^first, "first", {:failed, :output_unavailable}}
    assert_receive {:DOWN, ^monitor, :process, ^first, :normal}
    assert_receive {:test_audio_output, ^second_sink, _}
  end

  test "multiple output sinks follow one participant cursor and stop together" do
    observe_pressure()
    second_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())

    {player, first_sink} =
      start_player(asset(:binary.copy(<<4::little-signed-16>>, 960)), "shared",
        extra_sink: second_sink
      )

    assert_receive {:test_audio_output, ^first_sink, first}
    assert_receive {:test_audio_output, ^second_sink, second}
    assert first.payload == second.payload
    assert first.correlation_id == second.correlation_id

    assert_receive {:player_pressure, ^player, %{depth: 2, limit: 2},
                    %{kind: :wait, status: :queued}}

    monitor = Process.monitor(player)
    Player.stop(player)
    assert_receive {:test_audio_output_interrupt, ^first_sink, _turn, _played}
    assert_receive {:test_audio_output_interrupt, ^second_sink, _turn, _played}
    assert_receive {:vxpipe_wait_playback, ^player, "shared", :stopped}
    assert_receive {:DOWN, ^monitor, :process, ^player, :normal}
    assert_receive {:player_pressure, ^player, %{depth: 0, limit: 2}, %{status: :stopped}}
  end

  test "adding and replacing sinks retains the participant cursor and ignores retired outputs" do
    asset = asset(for i <- 0..499, into: <<>>, do: :binary.copy(<<i::little-signed-16>>, 960))
    {player, first} = start_player(asset, "changing")
    assert_receive {:test_audio_output, ^first, _}
    assert :ok = TestAudioOutputSink.playback_progress(first, 3_000, 3_000)
    Player.pause(player)
    assert_receive {:vxpipe_wait_playback, ^player, "changing", {:paused, 144_000}}
    flush_outputs(first)
    second = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())
    sinks = %{"connection-changing" => first, "second" => second}

    assert {:error, :stale_episode} =
             Player.reconcile(player, %{attempt_id: "old-attempt", generation: 1}, sinks)

    assert {:error, :stale_episode} =
             Player.reconcile(player, %{attempt_id: "attempt", generation: 2}, sinks)

    assert :ok = Player.reconcile(player, %{attempt_id: "attempt", generation: 1}, sinks)
    Player.resume(player)
    assert_receive {:test_audio_output, ^first, old_frame}
    assert_receive {:test_audio_output, ^second, frame}
    assert frame.payload == :binary.copy(<<150::little-signed-16>>, 960)
    assert frame.payload == old_frame.payload
    assert frame.correlation_id == old_frame.correlation_id

    replacement = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())
    sinks = %{"connection-changing" => replacement, "second" => second}
    assert :ok = Player.reconcile(player, %{attempt_id: "attempt", generation: 1}, sinks)
    flush_outputs(first)
    assert_receive {:test_audio_output, ^replacement, replaced_frame}
    assert_receive {:test_audio_output, ^second, retained_frame}, 1_000
    retained_frame = await_payload(second, retained_frame, replaced_frame.payload)
    assert replaced_frame.correlation_id == retained_frame.correlation_id
    refute_received {:test_audio_output, ^first, _}
    Player.stop(player)
    assert_receive {:vxpipe_wait_playback, ^player, "changing", :stopped}
  end

  test "finite cues await final drain on every output and carry the held generation" do
    second =
      start_supervised!({TestAudioOutputSink, observer: self(), defer_drain: true},
        id: make_ref()
      )

    {player, first} =
      start_player(asset(:binary.copy(<<1, 0>>, 960)), "cue-drain",
        loop: false,
        output_generation: 2,
        extra_sink: second
      )

    assert_receive {:test_audio_output, ^first, frame}
    assert Map.get(frame, :output_generation) == 2
    assert_receive {:test_audio_output_finish, ^first, _}
    assert_receive {:test_audio_output_finish, ^second, _}
    complete(first)
    complete(second)
    assert_receive {:test_audio_output_drain, ^first}
    assert_receive {:test_audio_output_drain, ^second}
    refute_receive {:vxpipe_wait_playback, ^player, "cue-drain", :completed}
    assert :ok = GenServer.call(second, :complete_drain)
    assert_receive {:vxpipe_wait_playback, ^player, "cue-drain", :completed}
  end

  for stage <- [:push, :playback] do
    test "loss of one wait sink during #{stage} keeps the surviving sink on the same cursor" do
      second = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())
      pcm = for i <- 0..9, into: <<>>, do: :binary.copy(<<i::little-signed-16>>, 960)

      {player, first} =
        start_player(asset(pcm), "surviving",
          extra_sink: second,
          block_output: unquote(stage) == :push
        )

      assert_receive {:test_audio_output, ^first, _}
      assert_receive {:test_audio_output, ^second, frame}
      assert frame.payload == :binary.copy(<<0::little-signed-16>>, 960)
      monitor = Process.monitor(first)
      Process.exit(first, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^first, _}
      assert_receive {:test_audio_output, ^second, next}
      assert next.payload == :binary.copy(<<1::little-signed-16>>, 960)
      Player.stop(player)
      assert_receive {:vxpipe_wait_playback, ^player, "surviving", :stopped}
    end
  end

  # Frames already queued for a retained sink keep flowing; skip forward to the first frame
  # that the replacement also received.
  defp await_payload(_sink, %{payload: payload} = frame, payload), do: frame

  defp await_payload(sink, _frame, payload) do
    assert_receive {:test_audio_output, ^sink, frame}, 1_000
    await_payload(sink, frame, payload)
  end

  defp flush_outputs(sink) do
    receive do
      {:test_audio_output, ^sink, _frame} -> flush_outputs(sink)
    after
      0 -> :ok
    end
  end

  defp observe_pressure do
    token = make_ref()
    owner = self()

    assert :ok =
             :telemetry.attach(
               token,
               [:vxpipe, :call_engine, :wait_sounds, :pressure],
               fn _, measurements, metadata, _ ->
                 send(owner, {:player_pressure, self(), measurements, metadata})
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(token) end)
  end

  defp start_player(asset, episode, options \\ []) do
    sink =
      start_supervised!(
        {TestAudioOutputSink,
         observer: self(), block_output: Keyword.get(options, :block_output, false)},
        id: make_ref()
      )

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
