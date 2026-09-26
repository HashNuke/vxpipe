defmodule Vxpipe.CallEngine.Speech.Duplex.OutputSegmenterTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Duplex.OutputSegmenter

  @loud 6_000
  @onset 500
  @silence 0
  @sample_rate 1_000
  @frame_ms 10

  describe "burst gating" do
    test "opens on an active frame and closes after the silence gap" do
      segmenter = new(gap_ms: 30)

      {segmenter, [open]} = push(segmenter, [@silence, @silence, @loud])
      assert {:open, output_ref} = open

      {segmenter, [audio]} = OutputSegmenter.admitted(segmenter, output_ref)
      assert {:audio, ^output_ref, pcm} = audio
      assert byte_size(pcm) == 3 * frame_bytes()

      {segmenter, events} = push(segmenter, [@silence, @silence])
      assert Enum.all?(events, &match?({:audio, ^output_ref, _}, &1))

      {_segmenter, events} = push(segmenter, [@silence])
      assert {:close, ^output_ref} = List.last(events)
    end

    test "keeps short pauses inside one burst" do
      segmenter = new(gap_ms: 100)

      {segmenter, [open]} = push(segmenter, [@loud])
      assert {:open, output_ref} = open
      {segmenter, _events} = OutputSegmenter.admitted(segmenter, output_ref)

      {segmenter, events} = push(segmenter, [@onset, @loud, @loud])
      assert Enum.all?(events, &match?({:audio, ^output_ref, _}, &1))
      assert OutputSegmenter.burst?(segmenter)
    end

    test "retains only the pre-roll window of silence before a burst" do
      segmenter = new(pre_roll_ms: 50, gap_ms: 20)

      {segmenter, []} = push(segmenter, List.duplicate(@silence, 10))
      {segmenter, [open]} = push(segmenter, [@loud])
      assert {:open, output_ref} = open

      {_segmenter, [audio]} = OutputSegmenter.admitted(segmenter, output_ref)
      assert {:audio, ^output_ref, pcm} = audio
      assert byte_size(pcm) == 6 * frame_bytes()
    end

    test "a quiet word onset below activation is replayed through the pre-roll" do
      segmenter = new(pre_roll_ms: 50, gap_ms: 20)

      {segmenter, [open]} = push(segmenter, [@onset, @loud])
      assert {:open, output_ref} = open

      {_segmenter, [audio]} = OutputSegmenter.admitted(segmenter, output_ref)
      assert {:audio, ^output_ref, pcm} = audio
      assert byte_size(pcm) == 2 * frame_bytes()
      assert :binary.part(pcm, 0, frame_bytes()) == frame(@onset)
    end

    test "fails explicitly when pre-admission buffering exceeds the receive buffer" do
      segmenter = new(buffer_ms: 30)

      {segmenter, [open]} = push(segmenter, [@loud])
      assert {:open, _output_ref} = open

      {segmenter, _events} = push(segmenter, [@loud, @loud])
      assert {:error, :buffer_overflow, _segmenter} = push(segmenter, [@loud])

      assert {:error, :buffer_overflow, _segmenter} =
               push(new(buffer_ms: 30), [@loud, @loud, @loud, @loud])
    end

    test "a complete burst arriving before admission retains its bounded audio" do
      segmenter = new(gap_ms: 20)
      {segmenter, events} = push(segmenter, [@loud, @silence, @silence])
      assert [{:open, output_ref}, {:close, closed_ref}] = events
      assert closed_ref == output_ref

      {_segmenter, [{:audio, ^output_ref, pcm}]} =
        OutputSegmenter.admitted(segmenter, output_ref)

      assert pcm == frame(@loud) <> frame(@silence) <> frame(@silence)
    end
  end

  describe "fragment alignment" do
    test "the first fragment fixes the provider offset for the burst" do
      segmenter = new(gap_ms: 500)

      {segmenter, [open]} = push(segmenter, [@loud])
      assert {:open, output_ref} = open
      {segmenter, _events} = OutputSegmenter.admitted(segmenter, output_ref)
      {segmenter, _events} = push(segmenter, List.duplicate(@loud, 40))

      {segmenter, [first]} = OutputSegmenter.fragment(segmenter, fragment("Hi", 1_000, 1_100))
      assert {:transcript, ^output_ref, "Hi", 0, 100} = first

      {_segmenter, [second]} =
        OutputSegmenter.fragment(segmenter, fragment(" there", 1_100, 1_250))

      assert {:transcript, ^output_ref, " there", 100, 250} = second
    end

    test "a fragment whose audio already played attaches to the earlier output" do
      segmenter = new(gap_ms: 20)

      {segmenter, [open]} = push(segmenter, [@loud])
      assert {:open, output_ref} = open
      {segmenter, _events} = OutputSegmenter.admitted(segmenter, output_ref)

      {segmenter, [first]} = OutputSegmenter.fragment(segmenter, fragment("done", 1_000, 1_020))
      assert {:transcript, ^output_ref, "done", 0, 20} = first

      {segmenter, events} = push(segmenter, [@silence, @silence])
      assert {:close, ^output_ref} = List.last(events)

      {_segmenter, [late]} = OutputSegmenter.fragment(segmenter, fragment("late", 1_000, 1_010))
      assert {:transcript, ^output_ref, "late", 0, 10} = late
    end

    test "drops and counts a fragment with no matching audio after the timeout" do
      segmenter = new(gap_ms: 100, fragment_timeout_ms: 20)

      {segmenter, [open]} = push(segmenter, [@loud])
      assert {:open, output_ref} = open
      {segmenter, _events} = OutputSegmenter.admitted(segmenter, output_ref)

      {segmenter, [first]} = OutputSegmenter.fragment(segmenter, fragment("base", 1_000, 1_020))
      assert {:transcript, ^output_ref, "base", 0, 20} = first

      {segmenter, []} = OutputSegmenter.fragment(segmenter, fragment("far", 9_000, 9_100))

      {segmenter, events} = push(segmenter, [@loud, @loud, @loud])
      assert Enum.any?(events, &match?({:dropped, "far"}, &1))
      assert OutputSegmenter.dropped(segmenter) == 1
    end
  end

  test "rejects malformed configuration" do
    assert {:error, :invalid_configuration} = OutputSegmenter.new(sample_rate: 0)
    assert {:error, :invalid_configuration} = OutputSegmenter.new(gap_ms: 0)
    assert {:error, :invalid_configuration} = OutputSegmenter.new(pre_roll_ms: -1)

    assert {:error, :invalid_configuration} =
             OutputSegmenter.new(
               sample_rate: @sample_rate,
               frame_ms: @frame_ms,
               silence_floor: 0,
               activation_threshold: 100,
               deactivation_threshold: 200
             )
  end

  defp new(options) do
    config = Keyword.merge([sample_rate: @sample_rate, frame_ms: @frame_ms], options)
    {:ok, segmenter} = OutputSegmenter.new(config)
    segmenter
  end

  # push/2 maps frame sample values to PCM; an empty list only re-checks held fragments.
  defp push(segmenter, frames) do
    pcm = frames |> Enum.map(&frame/1) |> IO.iodata_to_binary()
    OutputSegmenter.push_pcm(segmenter, pcm)
  end

  defp frame(value), do: :binary.copy(<<value::signed-little-16>>, frame_samples())

  defp frame_samples, do: div(@sample_rate * @frame_ms, 1_000)
  defp frame_bytes, do: frame_samples() * 2

  defp fragment(text, start_ms, end_ms),
    do: %{text: text, start_ms: start_ms, end_ms: end_ms}
end
