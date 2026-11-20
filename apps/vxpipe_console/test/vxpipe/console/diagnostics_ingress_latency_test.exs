defmodule Vxpipe.Console.DiagnosticsIngressLatencyTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.Test.{DiagnosticsIngressLatency, DiagnosticsSchedule}

  test "uses fixed frame populations and nearest-rank p95, including delayed receipts" do
    samples = samples(:warm, 1, 1)
    rows = Map.fetch!(samples, 0)
    # Exactly 32 of 625 measured frames are slow; the last receipt is outside
    # the audio interval and must remain in the population.
    rows =
      Enum.map(rows, fn row ->
        if row.sequence >= 750, do: %{row | provider_us: row.ingress_us + 9_000}, else: row
      end)

    assert %{count: 625, p95_us: 9_000} =
             DiagnosticsIngressLatency.summarize(%{0 => rows}, 1, 1, :warm)
  end

  test "keeps independent participants and validates every warm-up frame too" do
    samples = samples(:warm, 2, 2)
    assert %{count: 2_500, p95_us: 10} = DiagnosticsIngressLatency.summarize(samples, 2, 2, :warm)

    for bad <- [
          Map.delete(samples, 3),
          Map.put(samples, 0, tl(samples[0])),
          Map.update!(samples, 0, &Enum.reverse/1),
          Map.update!(samples, 0, fn [first | rest] ->
            [%{first | provider_us: first.ingress_us - 1} | rest]
          end)
        ] do
      assert_raise ArgumentError, fn -> DiagnosticsIngressLatency.summarize(bad, 2, 2, :warm) end
    end
  end

  test "rejects backwards clocks independently without rejecting overlapping frames" do
    for field <- [:ingress_us, :provider_us, :both] do
      rows = samples(:warm, 1, 1) |> Map.fetch!(0)
      rows = Enum.map(rows, &%{&1 | provider_us: &1.provider_us + 100_000})
      a = Enum.at(rows, 200)
      b = Enum.at(rows, 201)
      keys = if field == :both, do: [:ingress_us, :provider_us], else: [field]

      bad =
        rows
        |> List.replace_at(200, Map.merge(a, Map.take(b, keys)))
        |> List.replace_at(201, Map.merge(b, Map.take(a, keys)))

      assert %{count: 625, p95_us: 100_010} =
               DiagnosticsIngressLatency.summarize(%{0 => rows}, 1, 1, :warm)

      assert_raise ArgumentError, fn ->
        DiagnosticsIngressLatency.summarize(%{0 => bad}, 1, 1, :warm)
      end
    end
  end

  test "smoke includes every admitted frame" do
    assert %{count: 192, p95_us: 10} =
             DiagnosticsIngressLatency.summarize(samples(:smoke, 1, 1), 1, 1, :smoke)
  end

  defp samples(mode, rooms, humans) do
    for index <- 0..(rooms * humans - 1), into: %{} do
      rows =
        for sequence <- 0..(DiagnosticsSchedule.frame_count(index, rooms, humans, mode) - 1) do
          at = -1_000_000_000 + sequence * 32_000
          %{sequence: sequence, ingress_us: at, provider_us: at + 10}
        end

      {index, rows}
    end
  end
end
