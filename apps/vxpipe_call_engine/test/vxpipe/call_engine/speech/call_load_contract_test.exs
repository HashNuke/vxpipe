defmodule Vxpipe.CallEngine.Speech.CallLoadContractTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallLoad.{Metrics, Playback}

  test "percentiles preserve missing evidence and use nearest measured ranks" do
    assert Metrics.percentiles([]) == %{count: 0, p50: nil, p95: nil, p99: nil}
    assert Metrics.percentiles(Enum.to_list(1..100)) == %{count: 100, p50: 50, p95: 95, p99: 99}
  end

  test "run bounds require multiple calls and reject unbounded configurations" do
    assert :ok = Metrics.validate(10, 3, 90_000)
    assert {:error, :bounds} = Metrics.validate(11, 3, 90_000)
    assert {:error, :bounds} = Metrics.validate(1, 3, 90_000)
    assert {:error, :bounds} = Metrics.validate(10, 0, 90_000)
    assert {:error, :bounds} = Metrics.validate(10, 3, 300_000)
  end

  test "playback cannot claim more PCM than arrived or more elapsed time than consumed" do
    state = Playback.new(1_000)
    assert {:ok, state} = Playback.accept(state, 3_200, 16_000, 1_000)
    assert Playback.played_ms(state, 1_030) == 30
    assert Playback.played_ms(state, 1_500) == 100
    assert {:error, :output_bound} = Playback.accept(state, 1_000_001, 16_000, 1_000)
    assert Playback.played_ms(Playback.new(1_000), 9_000) == 0
  end
end
