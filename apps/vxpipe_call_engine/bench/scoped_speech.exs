# Isolated VM experiment. From apps/vxpipe_call_engine:
# MIX_ENV=test mix run bench/scoped_speech.exs /tmp/scoped-speech.json
ExUnit.start(seed: 0)

defmodule Vxpipe.CallEngine.ScopedSpeechBench do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.SpeechExperiment.Call

  @path List.first(System.argv()) || Path.join(System.tmp_dir!(), "scoped-speech.json")
  @rounds 8
  @warmup 1
  @maximum_concurrency max(1, div(System.schedulers_online(), 2))
  @paced_check? Enum.member?(System.argv(), "paced-check")
  @burst_check? Enum.member?(System.argv(), "burst-check")

  @tag timeout: 180_000
  @tag :capture_log
  test "bounded production room speech workload" do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    trials =
      for {lane, level} <- scenarios() do
        contexts = for _ <- 1..level, do: Call.start(:scoped)
        rounds = if lane == :paced, do: if(@paced_check?, do: 6, else: 2), else: @rounds
        process_before = :erlang.system_info(:process_count)
        memory_before = :erlang.memory(:processes_used)

        samples =
          for round <- 1..(rounds + @warmup), reduce: [] do
            samples ->
              results =
                contexts
                |> Task.async_stream(&Call.turn(&1, lane),
                  max_concurrency: level,
                  timeout: 15_000
                )
                |> Enum.map(fn {:ok, result} ->
                  assert result.counts == %{started: 1, final: 1, ended: 1, text: 1, completed: 1}
                  assert result.transcript == "E"
                  assert result.output == Call.pcm(20)
                  assert result.valid_correlations?
                  assert Enum.all?(result.metrics, fn {_metric, value} -> value >= 0 end)
                  result.metrics
                end)

              if round > @warmup, do: results ++ samples, else: samples
          end

        process_after = :erlang.system_info(:process_count)
        memory_after = :erlang.memory(:processes_used)

        Enum.each(contexts, &Call.stop/1)

        trial = %{
          lane: lane,
          concurrency: level,
          path: :production_native_stt,
          successful_turns: length(samples),
          metrics: summarize(samples),
          process_count_before: process_before,
          process_count_after: process_after,
          process_memory_before: memory_before,
          process_memory_after: memory_after,
          samples: samples
        }

        IO.puts("production native STT #{lane} n=#{level}: #{length(samples)} turns")

        trial
      end

    report = %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      maximum_concurrency: @maximum_concurrency,
      warmup_rounds: @warmup,
      paced_check: @paced_check?,
      burst_check: @burst_check?,
      input: "independent E PCM; 16kHz linear16; 60ms dot + 840ms gap",
      output: "independent E PCM; 16kHz linear16; 20ms dot + 280ms gap",
      playback: "immediate controlled acknowledgement at sink finish; not acoustic latency",
      comparison:
        "Historical paired legacy/scoped baselines remain in labnotes/20260919-1711-scoped-speech-*.json; this post-integration run exercises only the production native room path.",
      trials: trials,
      total_successful_turns: Enum.sum(Enum.map(trials, & &1.successful_turns))
    }

    File.write!(@path, JSON.encode!(report))
    IO.puts("Report: #{@path}")
  end

  defp scenarios do
    case Enum.at(System.argv(), 1) do
      "paced-check" ->
        [{:paced, @maximum_concurrency}]

      "burst-check" ->
        [{:burst, @maximum_concurrency}]

      _ ->
        [{:burst, @maximum_concurrency}, {:paced, @maximum_concurrency}]
    end
  end

  defp summarize(samples) do
    Map.new(Map.keys(hd(samples)), fn metric ->
      values = samples |> Enum.map(&Map.fetch!(&1, metric)) |> Enum.sort()
      count = length(values)

      {metric,
       %{
         p50: Enum.at(values, ceil(count * 0.50) - 1),
         p95: Enum.at(values, ceil(count * 0.95) - 1),
         p99: Enum.at(values, ceil(count * 0.99) - 1),
         max: List.last(values)
       }}
    end)
  end
end
