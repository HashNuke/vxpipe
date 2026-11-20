defmodule Vxpipe.CallEngine.Speech.SileroNativeThreadsTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Speech.Silero

  @moduletag :integration
  @moduletag :native_thread_contract

  test "loading the CPU Silero model creates no native worker pool" do
    before = MapSet.new(File.ls!("/proc/self/task"))
    assert {:ok, model} = Silero.load()
    created = MapSet.difference(MapSet.new(File.ls!("/proc/self/task")), before)

    assert MapSet.size(created) == 0,
           "Silero created #{MapSet.size(created)} native workers instead of using its calling thread"

    assert {:ok, stream, [probability]} =
             Silero.push(Silero.new(), model, :binary.copy(<<0>>, 1_024))

    assert stream.samples == 512
    assert probability < 0.35
  end

  test "patched native boundary rejects invalid thread counts before model loading" do
    for threads <- [-1, 1.5, "1", 2_147_483_648] do
      assert_raise ArgumentError, fn ->
        Ortex.load("missing-model.onnx", [:cpu], 3, threads)
      end
    end
  end

  test "legacy model loading arities remain available" do
    path = Application.app_dir(:vxpipe_call_engine, "priv/speech/silero_v6.2.3.onnx")
    assert %Ortex.Model{} = Ortex.load(path, [:cpu], 3)
    assert is_reference(Ortex.Native.init(path, [:cpu], 3))
  end
end
