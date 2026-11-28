defmodule Vxpipe.CallEngine.Speech.Silero.BatchTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Speech.Silero
  alias Vxpipe.CallEngine.Speech.Silero.Batch
  alias Vxpipe.Providers.Deepgram.LiveFixture

  test "every batch size matches independent recurrent streams in submitted order" do
    {:ok, model} = Silero.load()
    audio = File.read!(LiveFixture.pcm_path())

    Enum.reduce(1..16, %{}, fn size, streams ->
      ids = Enum.reverse(1..size)

      rows =
        for id <- ids do
          frame =
            binary_part(audio, rem((size * 101 + id * 313) * 2, byte_size(audio) - 1024), 1024)

          {state, packed} = Map.get(streams, id, {Silero.new(), Batch.initial_state()})
          {:ok, scalar, [p]} = Silero.push(state, model, frame)
          {id, frame, packed, scalar, p}
        end

      {:ok, results} =
        Batch.run(model, Enum.map(rows, fn {_, frame, packed, _, _} -> {frame, packed} end))

      assert length(results) == size

      Map.new(Enum.zip(rows, results), fn {{id, _, _, scalar, p}, {actual, packed}} ->
        assert_in_delta actual, p, 1.0e-6
        for threshold <- [0.35, 0.5], do: assert(actual >= threshold == p >= threshold)
        <<context::binary-size(256), hidden::binary-size(1024)>> = packed
        assert context == Nx.to_binary(scalar.context)
        expected = Nx.to_flat_list(scalar.recurrent)
        floats = for <<value::little-float-32 <- hidden>>, do: value
        Enum.zip_with(floats, expected, fn x, y -> assert_in_delta x, y, 1.0e-6 end)
        {id, {scalar, packed}}
      end)
    end)
  end

  test "fresh recurrent state reproduces the packaged reference trace" do
    {:ok, model} = Silero.load()
    frames = for <<pcm::binary-size(1024) <- File.read!(LiveFixture.pcm_path())>>, do: pcm
    reference = Path.expand("../../../fixtures/speech/silero_v6.2.3.f32", __DIR__) |> File.read!()
    expected = for <<p::little-float-32 <- reference>>, do: p
    assert length(expected) == length(frames)

    for _reset <- 1..2 do
      Enum.zip(frames, expected)
      |> Enum.reduce(Batch.initial_state(), fn {pcm, p}, state ->
        assert {:ok, [{actual, next}]} = Batch.run(model, [{pcm, state}])
        assert_in_delta actual, p, 1.0e-6
        next
      end)
    end
  end

  test "invalid rows return a fixed failure" do
    {:ok, model} = Silero.load()
    row = {:binary.copy(<<0>>, 1024), Batch.initial_state()}

    {pcm, packed} = row
    <<_::32, suffix::binary>> = packed
    nan_context = <<0x7FC00000::little-32, suffix::binary>>
    <<prefix::binary-size(1276), _::32>> = packed
    infinite_hidden = <<prefix::binary, 0x7F800000::little-32>>

    for rows <- [
          [],
          [row | :improper],
          List.duplicate(row, 17),
          [{<<1>>, packed}],
          [{pcm, <<>>}],
          [{pcm, nan_context}],
          [{pcm, infinite_hidden}]
        ] do
      assert {:error, :classification_failed} = Batch.run(model, rows)
    end
  end
end
