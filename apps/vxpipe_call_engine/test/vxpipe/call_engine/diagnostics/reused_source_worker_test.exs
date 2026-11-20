defmodule Vxpipe.CallEngine.Diagnostics.ReusedSourceWorkerTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SourceWorker}
  alias Vxpipe.CallEngine.Media.AudioFrame

  setup do
    {:ok, output} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    epoch = make_ref()

    worker =
      start_supervised!(
        {SourceWorker,
         mode: :operational_reuse,
         owner: self(),
         output: output,
         settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
         source_epoch: epoch,
         clock_id: "clock",
         source_id: "source",
         origin_us: -1_000_000,
         clock: fn -> 0 end,
         maximum_count: 8}
      )

    %{worker: worker, input: SourceWorker.handoff(worker), output: output, epoch: epoch}
  end

  test "reused results wait for accepted audio and emit boundaries without an inference runtime",
       ctx do
    offer(ctx, {:mapped_probabilities, 0, 0, 32_000, List.duplicate(0.9, 4), 0})
    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 1} = CaptureHandoff.stats(ctx.input)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    offer(ctx, {:audio, frame(ctx.epoch, 32_000, 2_048, -872)})

    assert {:acoustic_boundary, 0, :speech_started, 32_000, 0, 1_000_000, _, :partial_start} =
             packet(ctx)

    assert {:acoustic_progress, 0, 32_000, 34_048} = packet(ctx)

    offer(ctx, {:audio, %{frame(ctx.epoch, 34_048, 8_192, -360) | sequence_number: 2}})
    offer(ctx, {:mapped_probabilities, 0, 2_048, 34_048, List.duplicate(0.0, 16), 0})

    assert {:acoustic_boundary, 0, :speech_ended, 34_048, 128_000, 1_000_000, _, :partial_start} =
             packet(ctx)

    assert {:acoustic_progress, 0, 32_000, 42_240} = packet(ctx)

    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 0} = CaptureHandoff.stats(ctx.input)
  end

  test "reset discards waiting old results and ignores late retired-epoch results", ctx do
    offer(ctx, {:mapped_probabilities, 0, 0, 32_000, List.duplicate(0.9, 4), 0})
    offer(ctx, {:reset, 1, :provider_turn_settled, 0})
    assert {:reset, 1, :provider_turn_settled, 0} = packet(ctx)
    offer(ctx, {:mapped_probabilities, 0, 0, 32_000, List.duplicate(0.9, 4), 0})
    offer(ctx, {:audio, frame(ctx.epoch, 40_000, 2_048, -872)})
    offer(ctx, {:mapped_probabilities, 1, 0, 40_000, List.duplicate(0.9, 4), 0})

    assert {:acoustic_boundary, 1, :speech_started, 40_000, 0, 1_000_000, _, :partial_start} =
             packet(ctx)

    assert {:acoustic_progress, 1, 40_000, 42_048} = packet(ctx)

    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 0} = CaptureHandoff.stats(ctx.input)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "missing probability windows invalidate the epoch rather than joining unrelated speech",
       ctx do
    offer(ctx, {:audio, frame(ctx.epoch, 32_000, 8_192, -488)})
    offer(ctx, {:mapped_probabilities, 0, 0, 32_000, List.duplicate(0.9, 4), 0})
    assert {:acoustic_boundary, 0, :speech_started, _, _, _, _, _} = packet(ctx)
    assert {:acoustic_progress, 0, 32_000, 34_048} = packet(ctx)
    offer(ctx, {:mapped_probabilities, 0, 4_096, 36_096, List.duplicate(0.0, 4), 0})
    assert {:reset, 0, :audio_gap, 0} = packet(ctx)
    offer(ctx, {:mapped_probabilities, 0, 2_048, 34_048, List.duplicate(0.0, 4), 0})
    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 0} = CaptureHandoff.stats(ctx.input)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "source gaps invalidate waiting results until the operational epoch changes", ctx do
    offer(ctx, {:audio, frame(ctx.epoch, 32_000, 512, -968)})
    offer(ctx, {:mapped_probabilities, 0, 0, 32_000, List.duplicate(0.9, 4), 0})
    offer(ctx, {:audio, %{frame(ctx.epoch, 40_000, 512, -468) | sequence_number: 2}})
    assert {:reset, 0, :audio_gap, -468_000} = packet(ctx)
    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 0} = CaptureHandoff.stats(ctx.input)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "revocation and supervised shutdown release pending reuse reservations", ctx do
    offer(ctx, {:mapped_probabilities, 0, 0, 32_000, List.duplicate(0.9, 4), 0})
    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 1} = CaptureHandoff.stats(ctx.input)
    monitor = Process.monitor(ctx.worker)
    CaptureHandoff.close(ctx.output)
    send(ctx.worker, :check_grant)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert %{pending_count: 0, open?: false} = CaptureHandoff.stats(ctx.input)
  end

  test "input saturation retires an observer waiting for missing audio", ctx do
    packet = {:mapped_probabilities, 0, 0, 32_000, List.duplicate(0.9, 4), 0}
    for _ <- 1..8, do: offer(ctx, packet)
    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 8} = CaptureHandoff.stats(ctx.input)
    assert {:error, :full} = CaptureHandoff.offer(ctx.input, packet)
    monitor = Process.monitor(ctx.worker)
    send(ctx.worker, :check_grant)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert %{pending_count: 0, open?: false, overflow: 1} = CaptureHandoff.stats(ctx.input)
  end

  test "an uncaptured prefix cannot produce a later complete endpoint", ctx do
    offer(ctx, {:audio, frame(ctx.epoch, 43_000, 10_000, -375)})

    probabilities =
      List.duplicate(0.9, 4) ++
        List.duplicate(0.0, 16) ++
        List.duplicate(0.9, 4) ++ List.duplicate(0.0, 8)

    offer(ctx, {:mapped_probabilities, 0, 0, 32_000, probabilities, 0})
    assert {:reset, 0, :audio_gap, 0} = packet(ctx)
    offer(ctx, {:mapped_probabilities, 0, 16_384, 48_384, List.duplicate(0.0, 8), 0})
    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 0} = CaptureHandoff.stats(ctx.input)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "provider sample mapping passes through without acoustic work", ctx do
    mapping = {:provider_sample_mapping, make_ref(), 1_000, 50_000}
    offer(ctx, mapping)
    assert ^mapping = packet(ctx)
  end

  test "turn links pass through unchanged without acoustic work", ctx do
    link = {:turn_link, make_ref(), make_ref(), make_ref(), make_ref()}
    offer(ctx, link)
    assert ^link = packet(ctx)
    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 0} = CaptureHandoff.stats(ctx.input)
  end

  test "room completion keeps its original acceptance timestamp through the worker", ctx do
    completion = {:room_turn_completed, make_ref(), make_ref(), "turn", "command", -123}
    offer(ctx, completion)
    assert ^completion = packet(ctx)
  end

  test "response landmarks preserve their original time and exact output IDs", ctx do
    for kind <- [:first_response_text, :first_audio_start] do
      response = {:response_landmark, "turn", "command", "output", kind, -123}
      offer(ctx, response)
      assert ^response = packet(ctx)
    end
  end

  test "delayed mismatched reuse windows retain their original observation time", ctx do
    offer(ctx, {:audio, frame(ctx.epoch, 32_000, 8_192, -488)})
    offer(ctx, {:mapped_probabilities, 0, 0, 32_000, List.duplicate(0.9, 4), -200_000})
    assert {:acoustic_boundary, 0, :speech_started, _, _, _, _, _} = packet(ctx)
    assert {:acoustic_progress, 0, 32_000, 34_048} = packet(ctx)
    offer(ctx, {:mapped_probabilities, 0, 4_096, 36_096, List.duplicate(0.0, 4), -100_000})
    assert {:reset, 0, :audio_gap, -100_000} = packet(ctx)
  end

  test "missing reuse prefix retains the probability observation time", ctx do
    offer(ctx, {:audio, frame(ctx.epoch, 43_000, 10_000, -375)})

    probabilities =
      List.duplicate(0.9, 4) ++
        List.duplicate(0.0, 16) ++ List.duplicate(0.9, 4) ++ List.duplicate(0.0, 8)

    offer(ctx, {:mapped_probabilities, 0, 0, 32_000, probabilities, -100_000})
    assert {:reset, 0, :audio_gap, -100_000} = packet(ctx)
  end

  test "implicit reuse epoch transition retains the probability observation time", ctx do
    offer(ctx, {:audio, frame(ctx.epoch, 32_000, 8_192, -488)})
    offer(ctx, {:mapped_probabilities, 1, 0, 32_000, List.duplicate(0.9, 4), -100_000})
    assert {:reset, 1, :provider_turn_settled, -100_000} = packet(ctx)
  end

  defp offer(ctx, packet), do: assert(:ok == CaptureHandoff.offer(ctx.input, packet))

  defp packet(ctx) do
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, packet, charge} = CaptureHandoff.message(ctx.output, message)
    CaptureHandoff.release(ctx.output, charge, :processed)
    packet
  end

  defp frame(epoch, timestamp, samples, received) do
    %AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      connection_id: "connection",
      track_id: "audio",
      codec: :linear16,
      channels: 1,
      sample_rate: 16_000,
      timestamp: timestamp,
      sequence_number: 1,
      received_at: received,
      source_epoch: epoch,
      payload: :binary.copy(<<1, 0>>, samples)
    }
  end
end
