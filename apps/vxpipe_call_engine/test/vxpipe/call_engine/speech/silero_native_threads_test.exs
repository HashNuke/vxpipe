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

  test "sixteen rows cross one native boundary without starting ONNX workers" do
    alias Silero.Batch
    {:ok, model} = Silero.load()
    rows = List.duplicate({:binary.copy(<<0>>, 1024), Batch.initial_state()}, 16)
    before = MapSet.new(File.ls!("/proc/self/task"))
    function = {Ortex.Native, :silero_batch, 2}
    assert :erlang.trace_pattern(function, true, [:call_count]) == 1

    try do
      assert {:ok, results} = Batch.run(model, rows)
      assert length(results) == 16
      assert {:call_count, 1} = :erlang.trace_info(function, :call_count)
      assert MapSet.subset?(MapSet.new(File.ls!("/proc/self/task")), before)
    after
      :erlang.trace_pattern(function, false, [:call_count])
    end
  end

  test "warm inference uploads at most one changing input tensor per frame" do
    assert {:ok, model} = Silero.load()
    assert {:ok, stream, [_]} = Silero.push(Silero.new(), model, :binary.copy(<<0>>, 1_024))
    function = {Ortex.Backend, :from_binary, 3}
    assert :erlang.trace_pattern(function, true, [:call_count]) == 1
    :erlang.trace(self(), true, [:call])

    try do
      final =
        Enum.reduce(1..32, stream, fn sample, state ->
          audio = :binary.copy(<<sample::signed-little-16>>, 512)
          assert {:ok, next, [_]} = Silero.push(state, model, audio)
          next
        end)

      assert final.samples == 33 * 512
      assert {:call_count, count} = :erlang.trace_info(function, :call_count)

      assert count <= 32,
             "32 frames uploaded #{count} tensors, including repeated constant inputs"
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern(function, false, [:call_count])
    end
  end

  test "CPU Silero inference does not use the dirty I/O inference entry" do
    assert {:ok, model} = Silero.load()
    audio = :binary.copy(<<0>>, 1_024)
    assert {:ok, stream, [_]} = Silero.push(Silero.new(), model, audio)
    function = {Ortex.Native, :run, 2}
    cpu_function = {Ortex.Native, :run_cpu, 2}
    assert :erlang.trace_pattern(cpu_function, true, [:call_count]) == 1
    assert :erlang.trace_pattern(function, true, [:call_count]) == 1
    :erlang.trace(self(), true, [:call])

    try do
      assert {:ok, next, [probability]} = Silero.push(stream, model, audio)
      assert next.samples == 1_024
      assert probability < 0.35
      assert {:call_count, 0} = :erlang.trace_info(function, :call_count)
      assert {:call_count, 1} = :erlang.trace_info(cpu_function, :call_count)
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern(function, false, [:call_count])
      :erlang.trace_pattern(cpu_function, false, [:call_count])
    end
  end

  test "patched native boundary rejects invalid thread counts before model loading" do
    for threads <- [-1, 1.5, "1", 2_147_483_648] do
      assert_raise ArgumentError, fn ->
        Ortex.load("missing-model.onnx", [:cpu], 3, threads)
      end
    end
  end

  test "CPU and legacy inference entries preserve tensor results" do
    assert {:ok, model} = Silero.load()
    audio = Nx.iota({1, 576}, type: :f32) |> Nx.divide(32_768)
    recurrent = Nx.broadcast(Nx.tensor(0, type: :f32), {2, 1, 128})
    inputs = {audio, recurrent, model.sample_rate}
    legacy = Ortex.run(model.resource, inputs)
    cpu = Ortex.run_cpu(model.resource, inputs)

    assert Enum.map(Tuple.to_list(cpu), &Nx.to_binary/1) ==
             Enum.map(Tuple.to_list(legacy), &Nx.to_binary/1)
  end

  test "legacy model loading arities remain available" do
    path = Application.app_dir(:vxpipe_call_engine, "priv/speech/silero_v6.2.3.onnx")
    assert %Ortex.Model{} = Ortex.load(path, [:cpu], 3)
    assert is_reference(Ortex.Native.init(path, [:cpu], 3))
  end
end
