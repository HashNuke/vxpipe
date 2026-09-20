# Run from apps/vxpipe_gateway with at most half of an eight-scheduler host:
# ERL_FLAGS="+S 4:4" MIX_ENV=test mix run bench/opus_input_latency.exs /tmp/vxpipe-opus-input-latency.json
#
# Isolated codec-boundary diagnostic. It does not start calls or contact providers.

defmodule Vxpipe.Gateway.WebRTC.OpusInputLatencyBench do
  alias Membrane.Opus.Encoder.Native
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.Gateway.WebRTC.SpeechInput

  @application_voip 2_048
  @automatic_bitrate -1_000
  @signal_voice 3_001
  @workers 4
  @warmup_rounds 500
  @measured_rounds 3_000
  @paced_calls 32
  @paced_warmup_rounds 10
  @paced_measured_rounds 100
  @packet_interval_us 20_000
  @track %{track_id: "track-input", codec: :opus, sample_rate: 48_000, channels: 2}

  def run(output_path) do
    previous_wall_time = :erlang.system_flag(:scheduler_wall_time, true)

    try do
      results =
        for scenario <- [
              :baseline_mono,
              :normalized_mono,
              :normalized_stereo,
              :normalized_transition,
              :linear16_stereo
            ] do
          measure(scenario)
        end

      paced_results =
        for scenario <- [
              :baseline_mono,
              :normalized_stereo,
              :baseline_transition,
              :normalized_transition
            ] do
          measure_paced(scenario)
        end

      report = %{
        elixir: System.version(),
        otp: System.otp_release(),
        schedulers: System.schedulers_online(),
        workers: @workers,
        warmup_rounds_per_worker: @warmup_rounds,
        measured_rounds_per_worker: @measured_rounds,
        scenarios: results,
        paced_calls: @paced_calls,
        paced_packet_interval_us: @packet_interval_us,
        paced_scenarios: paced_results
      }

      File.write!(output_path, JSON.encode!(report))
      IO.puts("Opus input measurements written to #{output_path}")
      Enum.each(results, &print_result/1)
      Enum.each(paced_results, &print_paced_result/1)
    after
      :erlang.system_flag(:scheduler_wall_time, previous_wall_time)
    end
  end

  defp measure_paced(scenario) do
    memory_before = :erlang.memory(:total)
    schedulers_before = scheduler_wall_time()
    started = System.monotonic_time(:microsecond)

    samples =
      1..@paced_calls
      |> Task.async_stream(
        fn worker -> paced_worker(scenario, worker) end,
        max_concurrency: @paced_calls,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.flat_map(fn {:ok, values} -> values end)

    wall_us = System.monotonic_time(:microsecond) - started
    schedulers_after = scheduler_wall_time()
    memory_after = :erlang.memory(:total)
    completion = Enum.map(samples, &(&1.delivery_lag_us + &1.operation_us))

    %{
      scenario: scenario,
      calls: @paced_calls,
      operations: length(samples),
      operation_latency_us: stats(Enum.map(samples, & &1.operation_us)),
      delivery_lag_us: stats(Enum.map(samples, & &1.delivery_lag_us)),
      delivery_completion_us: stats(completion),
      missed_packet_deadlines: Enum.count(completion, &(&1 > @packet_interval_us)),
      wall_us: wall_us,
      scheduler_utilization: scheduler_utilization(schedulers_before, schedulers_after),
      memory_delta_bytes: memory_after - memory_before
    }
  end

  defp measure(scenario) do
    memory_before = :erlang.memory(:total)
    schedulers_before = scheduler_wall_time()
    started = System.monotonic_time(:microsecond)

    samples =
      1..@workers
      |> Task.async_stream(
        fn worker -> worker(scenario, worker) end,
        max_concurrency: @workers,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.flat_map(fn {:ok, values} -> values end)

    wall_us = System.monotonic_time(:microsecond) - started
    schedulers_after = scheduler_wall_time()
    memory_after = :erlang.memory(:total)

    %{
      scenario: scenario,
      operations: length(samples),
      latency_us: stats(samples),
      wall_us: wall_us,
      operations_per_second: Float.round(length(samples) * 1_000_000 / wall_us, 1),
      scheduler_utilization: scheduler_utilization(schedulers_before, schedulers_after),
      memory_delta_bytes: memory_after - memory_before
    }
  end

  defp worker(scenario, worker) do
    {frame, input} = setup(scenario, worker)

    for round <- 1..@warmup_rounds do
      :ok = execute(scenario, frame_for_round(frame, round), input)
    end

    for round <- 1..@measured_rounds do
      started = System.monotonic_time(:nanosecond)
      :ok = execute(scenario, frame_for_round(frame, round), input)
      div(System.monotonic_time(:nanosecond) - started, 1_000)
    end
  end

  defp paced_worker(scenario, worker) do
    {frame, input} = setup(scenario, worker)
    first_deadline = System.monotonic_time(:microsecond) + @packet_interval_us

    1..(@paced_warmup_rounds + @paced_measured_rounds)
    |> Enum.map(fn round ->
      deadline = first_deadline + (round - 1) * @packet_interval_us
      wait_until(deadline)
      started = System.monotonic_time(:microsecond)
      :ok = execute(scenario, frame_for_round(frame, round), input)

      %{
        delivery_lag_us: max(started - deadline, 0),
        operation_us: System.monotonic_time(:microsecond) - started
      }
    end)
    |> Enum.drop(@paced_warmup_rounds)
  end

  defp wait_until(deadline) do
    remaining_us = deadline - System.monotonic_time(:microsecond)

    if remaining_us > 0 do
      receive do
      after
        div(remaining_us + 999, 1_000) -> :ok
      end
    end
  end

  defp setup(:baseline_mono, worker), do: {frame(opus_packet(1), worker), nil}

  defp setup(:normalized_mono, worker) do
    assert_configured(frame(opus_packet(1), worker), target(:opus))
  end

  defp setup(:normalized_stereo, worker) do
    assert_configured(frame(opus_packet(2), worker), target(:opus))
  end

  defp setup(:normalized_transition, worker) do
    {_frame, input} = assert_configured(frame(opus_packet(1), worker), target(:opus))

    frames =
      Enum.map([1, 1, 2, 2, 1, 1], fn channels -> frame(opus_packet(channels), worker) end)

    {frames, input}
  end

  defp setup(:baseline_transition, worker) do
    frames =
      Enum.map([1, 1, 2, 2, 1, 1], fn channels -> frame(opus_packet(channels), worker) end)

    {frames, nil}
  end

  defp setup(:linear16_stereo, worker) do
    assert_configured(frame(opus_packet(2), worker), target(:linear16))
  end

  defp assert_configured(frame, target) do
    {:ok, _output, input} = SpeechInput.configure(@track, target)
    {frame, input}
  end

  defp execute(:baseline_mono, %AudioFrame{payload: payload}, nil)
       when is_binary(payload) and byte_size(payload) > 0,
       do: :ok

  defp execute(:baseline_transition, %AudioFrame{payload: payload}, nil)
       when is_binary(payload) and byte_size(payload) > 0,
       do: :ok

  defp execute(:normalized_mono, frame, input) do
    case SpeechInput.frame(frame, input) do
      {:ok, %AudioFrame{codec: :opus, channels: 1, payload: <<_::5, 0::1, _::2, _::binary>>}} ->
        :ok

      _invalid ->
        raise "mono normalization failed"
    end
  end

  defp execute(:normalized_stereo, frame, input) do
    case SpeechInput.frame(frame, input) do
      {:ok, %AudioFrame{codec: :opus, channels: 1, payload: <<_::5, 0::1, _::2, _::binary>>}} ->
        :ok

      _invalid ->
        raise "stereo Opus normalization failed"
    end
  end

  defp execute(:normalized_transition, frame, input) do
    case SpeechInput.frame(frame, input) do
      {:ok, %AudioFrame{codec: :opus, channels: 1, payload: <<_::5, 0::1, _::2, _::binary>>}} ->
        :ok

      _invalid ->
        raise "Opus channel transition normalization failed"
    end
  end

  defp execute(:linear16_stereo, frame, input) do
    case SpeechInput.frame(frame, input) do
      {:ok, %AudioFrame{codec: :linear16, channels: 1, payload: payload}}
      when byte_size(payload) == 1_920 ->
        :ok

      _invalid ->
        raise "stereo linear16 normalization failed"
    end
  end

  defp target(codec), do: %{codec: codec, sample_rate: 48_000, channels: 1}

  defp frame_for_round(frames, round) when is_list(frames),
    do: Enum.at(frames, rem(round - 1, length(frames)))

  defp frame_for_round(frame, _round), do: frame

  defp frame(payload, worker) do
    %AudioFrame{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-#{worker}",
      connection_id: "conn-#{worker}",
      track_id: "track-input",
      codec: :opus,
      sample_rate: 48_000,
      channels: 2,
      sequence_number: 1,
      timestamp: 960,
      payload: payload,
      received_at: 1_000
    }
  end

  defp opus_packet(channels) do
    encoder =
      Native.create(48_000, channels, @application_voip, @automatic_bitrate, @signal_voice)

    pcm =
      for sample <- 0..959, channel <- 1..channels, into: <<>> do
        frequency = if channel == 1, do: 440, else: 660
        value = round(:math.sin(2 * :math.pi() * frequency * sample / 48_000) * 16_000)
        <<value::little-signed-16>>
      end

    {:ok, payload} = Native.encode_packet(encoder, pcm, 960)
    payload
  end

  defp stats(values) do
    sorted = Enum.sort(values)

    %{
      minimum: hd(sorted),
      p50: percentile(sorted, 0.50),
      p95: percentile(sorted, 0.95),
      p99: percentile(sorted, 0.99),
      maximum: List.last(sorted)
    }
  end

  defp percentile(sorted, fraction) do
    Enum.at(sorted, max(ceil(length(sorted) * fraction) - 1, 0))
  end

  defp scheduler_wall_time do
    :erlang.statistics(:scheduler_wall_time)
    |> Enum.filter(fn {id, _active, _total} -> id <= System.schedulers_online() end)
    |> Map.new(fn {id, active, total} -> {id, {active, total}} end)
  end

  defp scheduler_utilization(before, after_snapshot) do
    per_scheduler =
      Enum.map(after_snapshot, fn {id, {active_after, total_after}} ->
        {active_before, total_before} = Map.fetch!(before, id)
        total = total_after - total_before
        active = active_after - active_before
        if total > 0, do: active / total, else: 0.0
      end)

    %{
      average: Float.round(Enum.sum(per_scheduler) / length(per_scheduler), 4),
      maximum: Float.round(Enum.max(per_scheduler), 4)
    }
  end

  defp print_result(result) do
    latency = result.latency_us

    IO.puts(
      "#{result.scenario}: p50=#{latency.p50}us p95=#{latency.p95}us " <>
        "p99=#{latency.p99}us max=#{latency.maximum}us " <>
        "throughput=#{result.operations_per_second}/s"
    )
  end

  defp print_paced_result(result) do
    operation = result.operation_latency_us
    lag = result.delivery_lag_us
    completion = result.delivery_completion_us

    IO.puts(
      "paced #{result.scenario} at #{result.calls} calls: " <>
        "operation p50=#{operation.p50}us p95=#{operation.p95}us p99=#{operation.p99}us; " <>
        "delivery lag p50=#{lag.p50}us p95=#{lag.p95}us p99=#{lag.p99}us; " <>
        "completion p99=#{completion.p99}us missed=#{result.missed_packet_deadlines}"
    )
  end
end

output_path =
  List.first(System.argv()) || Path.join(System.tmp_dir!(), "vxpipe-opus-input-latency.json")

Vxpipe.Gateway.WebRTC.OpusInputLatencyBench.run(output_path)
