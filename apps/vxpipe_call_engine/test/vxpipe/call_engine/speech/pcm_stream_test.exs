defmodule Vxpipe.CallEngine.Speech.PCMStreamTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Speech.PCMStream

  test "reassembles fragmented signed 16-bit samples before exposing credited chunks" do
    assert {:ok, first, []} = PCMStream.feed(PCMStream.new(), <<1>>)
    assert {:ok, final, [<<1, 0, 2, 0>>]} = PCMStream.feed(first, <<0, 2, 0>>)
    assert :ok = PCMStream.finish(final)
  end

  test "bounds each delivered chunk while preserving the exact PCM stream" do
    pcm = :binary.copy(<<1, 0>>, 40_000)
    assert {:ok, final, chunks} = PCMStream.feed(PCMStream.new(), pcm)
    assert IO.iodata_to_binary(chunks) == pcm
    assert Enum.all?(chunks, &(byte_size(&1) <= 65_536 and rem(byte_size(&1), 2) == 0))
    assert :ok = PCMStream.finish(final)
  end

  test "rejects empty, truncated and over-budget response streams" do
    assert {:error, :invalid_audio} = PCMStream.finish(PCMStream.new())
    assert {:ok, partial, []} = PCMStream.feed(PCMStream.new(), <<1>>)
    assert {:error, :invalid_audio} = PCMStream.finish(partial)
    assert {:ok, full, [<<1, 0>>]} = PCMStream.feed(PCMStream.new(2), <<1, 0>>)
    assert {:error, :invalid_audio} = PCMStream.feed(full, <<2, 0>>)
  end
end
