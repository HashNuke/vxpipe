# Isolated VM experiment. From apps/vxpipe_call_engine:
# MIX_ENV=test mix run bench/scoped_speech.exs /tmp/scoped-speech.json
ExUnit.start(seed: 0)

defmodule Vxpipe.CallEngine.ScopedSpeechBench do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.SpeechExperiment.{Call, Scope}
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT

  @path List.first(System.argv()) || Path.join(System.tmp_dir!(), "scoped-speech.json")
  @rounds 20
  @warmup 3
  @paced_check? Enum.member?(System.argv(), "paced-check")
  @burst_check? Enum.member?(System.argv(), "burst-check")

  @tag timeout: 180_000
  @tag :capture_log
  test "paired real room speech workload, including held same-scope initialization" do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    trials =
      for repeat <- 1..3,
          {lane, level, held?} <- scenarios(),
          path <- if(rem(repeat, 2) == 1, do: [:legacy, :scoped], else: [:scoped, :legacy]) do
        contexts = for _ <- 1..level, do: Call.start(path)
        held = if held?, do: hold(hd(contexts).scope)
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

        if held do
          %{control: control, worker: worker, monitor: monitor} = held
          refute_received {:DOWN, ^monitor, :process, ^worker, _}
          :ok = GenServer.call(control, :close)
          assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
        end

        Enum.each(contexts, &Call.stop/1)

        trial = %{
          repeat: repeat,
          lane: lane,
          concurrency: level,
          path: path,
          held_start: held?,
          successful_turns: length(samples),
          metrics: summarize(samples),
          process_count_before: process_before,
          process_count_after: process_after,
          process_memory_before: memory_before,
          process_memory_after: memory_after,
          samples: samples
        }

        IO.puts(
          "#{path} #{lane} n=#{level} held=#{held?} repeat=#{repeat}: #{length(samples)} turns"
        )

        trial
      end

    report = %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      warmup_rounds: @warmup,
      paced_check: @paced_check?,
      burst_check: @burst_check?,
      input: "independent E PCM; 16kHz linear16; 60ms dot + 840ms gap",
      output: "independent E PCM; 16kHz linear16; 20ms dot + 280ms gap",
      playback: "immediate controlled acknowledgement at sink finish; not acoustic latency",
      trials: trials,
      total_successful_turns: Enum.sum(Enum.map(trials, & &1.successful_turns))
    }

    File.write!(@path, JSON.encode!(report))
    IO.puts("Report: #{@path}")
  end

  defp scenarios do
    case Enum.at(System.argv(), 1) do
      "paced-check" ->
        [{:paced, 8, false}]

      "burst-check" ->
        [{:burst, 32, false}]

      _ ->
        [
          {:burst, 1, false},
          {:burst, 8, false},
          {:burst, 32, false},
          {:burst, 32, true},
          {:paced, 1, false},
          {:paced, 8, false}
        ]
    end
  end

  defp hold(scope) do
    {:ok, config} = MorseCodeSTT.new([])

    {:ok, control} =
      Scope.start_session(scope,
        owner: self(),
        config: config,
        kind: :stt,
        observer: self(),
        hold_start: true,
        deadline: System.monotonic_time(:millisecond) + 60_000
      )

    assert_receive {:experiment_held, worker}, 1_000
    %{control: control, worker: worker, monitor: Process.monitor(worker)}
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
