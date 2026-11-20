defmodule Vxpipe.CallEngine.Diagnostics.SourceWorker do
  @moduledoc "Isolated acoustic source consumer; never emits speech-control events."
  use GenServer

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    AudioTimeline,
    CaptureHandoff,
    InferenceAdmission,
    SourcePort
  }

  alias Vxpipe.CallEngine.Speech.{ActivityBoundary, Silero}

  def child_spec(options),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary}

  def start_link(options) do
    case AttachmentLease.remaining(Keyword.get(options, :attachment_lease)) do
      0 -> {:error, :unavailable}
      timeout -> GenServer.start_link(__MODULE__, options, timeout: timeout)
    end
  end

  def handoff(worker, timeout \\ 5_000), do: GenServer.call(worker, :handoff, timeout)

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(options, :owner)
    output = Keyword.fetch!(options, :output)
    admission = Keyword.get(options, :admission)
    mode = Keyword.get(options, :mode, :benchmark_only)
    coordinator = Keyword.get(options, :coordinator)
    lease = Keyword.get(options, :attachment_lease)
    source_port = Keyword.get(options, :source_port)

    capture_options =
      Keyword.take(options, [:settings, :maximum_count, :maximum_bytes])
      |> Keyword.put(:owner, owner)
      |> Keyword.put(:provenance, output)

    with true <- AttachmentLease.current?(lease) and SourcePort.current?(source_port),
         true <- is_nil(coordinator) or (is_pid(coordinator) and node(coordinator) == node()),
         true <- output.owner == owner and CaptureHandoff.current?(output),
         true <- valid_admission?(mode, admission),
         {:ok, input} <- CaptureHandoff.new(self(), capture_options),
         true <- input.grant == output.grant and input.settings == output.settings do
      Enum.each([owner, output.receiver], &Process.monitor/1)
      if coordinator, do: Process.monitor(coordinator)
      if source_port, do: Process.monitor(source_port)
      if admission, do: Process.monitor(admission.runtime)

      timeline =
        AudioTimeline.new(
          Keyword.fetch!(options, :clock_id),
          Keyword.fetch!(options, :source_id),
          Keyword.fetch!(options, :source_epoch),
          Keyword.fetch!(options, :origin_us)
        )

      {:ok,
       %{
         input: input,
         output: output,
         coordinator: coordinator,
         source_port: source_port,
         attachment_lease: lease,
         admission: admission,
         mode: mode,
         reused: :queue.new(),
         reuse_invalid?: false,
         clean_reuse_epoch?: false,
         silence_prefix_frames: 0,
         timeline: timeline,
         origin_us: Keyword.fetch!(options, :origin_us),
         clock: Keyword.get(options, :clock, fn -> System.monotonic_time(:microsecond) end),
         timer: Process.send_after(self(), :check_grant, 250),
         queue: :queue.new(),
         inference: nil,
         stream: Silero.new(),
         boundary: ActivityBoundary.new(),
         epoch: 0,
         sample_origin: nil,
         partial?: true
       }}
    else
      _ -> {:stop, :unavailable}
    end
  end

  @impl true
  def handle_call(:handoff, _from, state) do
    if current?(state),
      do: {:reply, state.input, state},
      else: {:stop, :normal, {:error, :unavailable}, state}
  end

  @impl true
  def handle_info({:vxpipe_diagnostic_capture, _, _, _, _} = message, state) do
    case CaptureHandoff.message(state.input, message) do
      {:ok, packet, charge}
      when elem(packet, 0) in [
             :provider_landmark,
             :provider_sample_mapping,
             :turn_link,
             :room_turn_started,
             :room_turn_completed,
             :response_landmark,
             :barge_in_playback
           ] ->
        if current?(state) do
          case process(state, {packet, charge}) do
            {:ok, next} -> {:noreply, next}
            {:stop, next} -> {:stop, :normal, next}
          end
        else
          CaptureHandoff.release(state.input, charge, :discarded)
          {:stop, :normal, state}
        end

      {:ok, packet, charge} ->
        pump(%{state | queue: :queue.in({packet, charge}, state.queue)})

      {:error, :revoked} ->
        {:stop, :normal, state}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:vxpipe_speech_activity, reference, result},
        %{inference: %{reference: reference} = job} = state
      ) do
    CaptureHandoff.release(
      state.input,
      job.charge,
      if(current?(state), do: :processed, else: :discarded)
    )

    state = %{state | inference: nil}

    if current?(state) do
      case result do
        {:ok, %Silero{} = stream, probabilities} ->
          if valid_result?(stream, probabilities, job) do
            case boundaries(%{state | stream: stream}, probabilities) do
              {:ok, state} -> pump(state)
              {:stop, state} -> {:stop, :normal, state}
            end
          else
            reset_and_pump(state, :inference_failed)
          end

        _ ->
          reset_and_pump(state, :inference_failed)
      end
    else
      {:stop, :normal, state}
    end
  end

  def handle_info(:check_grant, state) do
    Process.cancel_timer(state.timer)

    if current?(state),
      do: {:noreply, %{state | timer: Process.send_after(self(), :check_grant, 250)}},
      else: {:stop, :normal, state}
  end

  def handle_info({:DOWN, _, :process, _, _}, state), do: {:stop, :normal, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    CaptureHandoff.close(state.input)
    if state.coordinator, do: CaptureHandoff.close(state.output)
    Process.cancel_timer(state.timer)

    if state.inference,
      do: CaptureHandoff.release(state.input, state.inference.charge, :discarded)

    Enum.each(:queue.to_list(state.reused), fn {_packet, charge} ->
      CaptureHandoff.release(state.input, charge, :discarded)
    end)

    Enum.each(:queue.to_list(state.queue), fn {_packet, charge} ->
      CaptureHandoff.release(state.input, charge, :discarded)
    end)

    discard_mailbox(state.input)
  end

  @impl true
  def format_status(status),
    do:
      status
      |> Map.put(:state, %{mode: status.state.mode})
      |> Map.put(:message, :redacted)
      |> Map.put(:reason, :redacted)
      |> Map.put(:log, [])

  defp pump(%{inference: job} = state) when job != nil, do: {:noreply, state}

  defp pump(state) do
    if current?(state) do
      case :queue.out(state.queue) do
        {:empty, _} ->
          {:noreply, state}

        {{:value, item}, queue} ->
          case process(%{state | queue: queue}, item) do
            {:ok, state} -> pump(state)
            {:stop, state} -> {:stop, :normal, state}
          end
      end
    else
      {:stop, :normal, state}
    end
  end

  defp process(
         %{mode: :operational_reuse} = state,
         {{:mapped_probabilities, epoch, _, _, _, at} = packet, charge}
       ) do
    cond do
      epoch < state.epoch or (epoch == state.epoch and state.reuse_invalid?) ->
        CaptureHandoff.release(state.input, charge, :discarded)
        {:ok, state}

      epoch > state.epoch ->
        case reuse_reset(state, epoch, :provider_turn_settled, at, false) do
          {:ok, next} ->
            # A first observed epoch is not evidence of a witnessed clean settlement.
            process(%{next | clean_reuse_epoch?: false}, {packet, charge})

          {:stop, next} ->
            discard(next, charge)
        end

      true ->
        reuse_drain(%{state | reused: :queue.in({packet, charge}, state.reused)})
    end
  end

  defp process(
         %{mode: :operational_reuse} = state,
         {{:reset, epoch, reason, at}, charge}
       ) do
    CaptureHandoff.release(state.input, charge, :processed)

    cond do
      epoch < state.epoch -> {:ok, state}
      epoch == state.epoch and reason == :provider_turn_settled -> {:ok, state}
      true -> reuse_reset(state, epoch, reason, at, reason != :provider_turn_settled)
    end
  end

  defp process(
         %{mode: :operational_reuse} = state,
         {{:probabilities, epoch, _, _, at}, charge}
       ) do
    CaptureHandoff.release(state.input, charge, :discarded)

    if epoch < state.epoch or (epoch == state.epoch and state.reuse_invalid?),
      do: {:ok, state},
      else: reuse_reset(state, epoch, :partial_start, at, true)
  end

  defp process(state, {{:audio, frame}, charge}) do
    case AudioTimeline.push(state.timeline, frame) do
      {:ok, timeline, pcm, notices} ->
        state = %{state | timeline: timeline}

        case audio_notices(state, notices, frame.received_at * 1_000) do
          {:ok, %{mode: :operational_reuse} = state} ->
            CaptureHandoff.release(state.input, charge, :processed)
            reuse_drain(state)

          {:ok, state} ->
            infer(state, pcm, charge)

          {:stop, state} ->
            discard(state, charge)
        end

      {:duplicate, _timeline} ->
        CaptureHandoff.release(state.input, charge, :processed)
        {:ok, state}

      {:error, :source_mismatch} ->
        discard(state, charge)

      {:error, _reason} ->
        CaptureHandoff.release(state.input, charge, :discarded)
        audio_notices(state, [:audio_gap], frame.received_at * 1_000)
    end
  end

  # Standalone acoustic state is independent of provider settlements.
  defp process(state, {{:reset, _epoch, :provider_turn_settled, _at}, charge}) do
    CaptureHandoff.release(state.input, charge, :processed)
    {:ok, state}
  end

  defp process(state, {{kind, _, _, _, _, _} = packet, charge})
       when kind in [:room_turn_started, :room_turn_completed] do
    CaptureHandoff.release(state.input, charge, :processed)
    emit(state, packet)
  end

  defp process(state, {{:barge_in_playback, _, _, _, _, _, _, _, _, _} = packet, charge}) do
    CaptureHandoff.release(state.input, charge, :processed)
    emit(state, packet)
  end

  defp process(state, {{:response_landmark, _, _, _, _, _} = packet, charge}) do
    CaptureHandoff.release(state.input, charge, :processed)
    emit(state, packet)
  end

  defp process(state, {{:turn_link, _, _, _, _} = packet, charge}) do
    CaptureHandoff.release(state.input, charge, :processed)
    emit(state, packet)
  end

  defp process(state, {{:provider_sample_mapping, _, _, _} = packet, charge}) do
    CaptureHandoff.release(state.input, charge, :processed)
    emit(state, packet)
  end

  defp process(state, {{:provider_landmark, _, _, _, _, _} = packet, charge}) do
    CaptureHandoff.release(state.input, charge, :processed)
    emit(state, packet)
  end

  defp process(state, {_packet, charge}), do: discard(state, charge)

  defp audio_notices(state, [], _at), do: {:ok, state}

  defp audio_notices(%{mode: :operational_reuse} = state, _notices, at),
    do: reuse_reset(state, state.epoch, :audio_gap, at, true)

  defp audio_notices(state, _notices, at), do: reset(state, :audio_gap, at)

  defp reuse_reset(state, epoch, reason, at, invalid?) do
    Enum.each(:queue.to_list(state.reused), fn {_, charge} ->
      CaptureHandoff.release(state.input, charge, :discarded)
    end)

    emit(
      %{
        state
        | epoch: epoch,
          reused: :queue.new(),
          reuse_invalid?: invalid?,
          clean_reuse_epoch?: reason == :provider_turn_settled and not invalid?,
          silence_prefix_frames: 0,
          boundary: ActivityBoundary.new(),
          sample_origin: nil,
          partial?: true
      },
      {:reset, epoch, reason, at}
    )
  end

  defp reuse_drain(state) do
    case :queue.out(state.reused) do
      {:empty, _} ->
        {:ok, state}

      {{:value, {{:mapped_probabilities, _, local, sample, probabilities, at}, charge}}, rest} ->
        last = state.timeline.clock.last_input
        count = 512 * length(probabilities)

        cond do
          local != state.boundary.samples or
              (state.sample_origin != nil and sample != state.sample_origin + local) ->
            reuse_reset(state, state.epoch, :audio_gap, at, true)

          last == nil or last.sample_timestamp + last.sample_count < sample + count ->
            {:ok, state}

          not captured_start?(state.timeline, sample) ->
            reuse_reset(state, state.epoch, :audio_gap, at, true)

          true ->
            CaptureHandoff.release(state.input, charge, :processed)
            next = %{state | reused: rest, sample_origin: state.sample_origin || sample}

            case boundaries(next, probabilities) do
              {:ok, next} -> reuse_drain(next)
              stop -> stop
            end
        end
    end
  end

  # Audio from one producer is ordered, and gaps invalidate the epoch. Once the
  # end is captured, an absent prefix cannot arrive later or be reconstructed.
  defp captured_start?(timeline, sample) do
    Enum.any?(timeline.clock.frames, fn frame ->
      sample >= frame.sample_timestamp and sample < frame.sample_timestamp + frame.sample_count
    end)
  end

  defp valid_admission?(:operational_reuse, nil), do: true

  defp valid_admission?(:benchmark_only, %InferenceAdmission{runtime: runtime}),
    do: Process.alive?(runtime)

  defp valid_admission?(_, _), do: false

  defp infer(state, "", charge) do
    CaptureHandoff.release(state.input, charge, :processed)
    {:ok, state}
  end

  defp infer(state, pcm, charge) do
    state = %{
      state
      | sample_origin: state.sample_origin || state.timeline.clock.last_input.sample_timestamp
    }

    bytes = byte_size(state.stream.pending) + byte_size(pcm)

    case InferenceAdmission.submit(state.admission, state.input, state.stream, pcm) do
      {:ok, reference} ->
        job = %{
          reference: reference,
          charge: charge,
          samples: state.stream.samples + 512 * div(bytes, 1_024),
          count: div(bytes, 1_024),
          pending: rem(bytes, 1_024)
        }

        {:ok, %{state | inference: job}}

      {:error, _reason} ->
        CaptureHandoff.release(state.input, charge, :discarded)
        reset(state, :inference_failed)
    end
  end

  defp valid_result?(stream, probabilities, job),
    do:
      stream.samples == job.samples and is_binary(stream.pending) and
        byte_size(stream.pending) == job.pending and probabilities?(probabilities, job.count)

  defp probabilities?([], 0), do: true

  defp probabilities?([p | rest], n) when n > 0 and is_number(p) and p >= 0 and p <= 1,
    do: probabilities?(rest, n - 1)

  defp probabilities?(_, _), do: false

  defp boundaries(state, probabilities) do
    Enum.reduce_while(probabilities, {:ok, state}, fn probability, {:ok, state} ->
      state = observe_silence_prefix(state, probability)
      {:ok, boundary, events} = ActivityBoundary.push(state.boundary, probability)

      case emit_boundaries(%{state | boundary: boundary}, events) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:stop, state} -> {:halt, {:stop, state}}
      end
    end)
    |> case do
      {:ok, next} ->
        emit(
          next,
          {:acoustic_progress, next.epoch, next.sample_origin,
           next.sample_origin + ActivityBoundary.finalized_samples(next.boundary)}
        )

      stopped ->
        stopped
    end
  end

  defp observe_silence_prefix(
         %{mode: :operational_reuse, clean_reuse_epoch?: true, partial?: true} = state,
         probability
       ) do
    profile = ActivityBoundary.profile()

    frames =
      if not state.boundary.speaking? and probability < profile.offset_threshold,
        do: state.silence_prefix_frames + 1,
        else: 0

    %{state | silence_prefix_frames: frames, partial?: frames < profile.offset_frames}
  end

  defp observe_silence_prefix(state, _probability), do: state

  defp emit_boundaries(state, []), do: {:ok, state}

  defp emit_boundaries(state, [{kind, relative_sample}]) do
    sample = state.sample_origin + relative_sample
    confirmed = state.clock.() - state.origin_us
    {offset, uncertainty, reason} = position(state, sample, confirmed)

    packet =
      {:acoustic_boundary, state.epoch, kind, sample, offset, confirmed, uncertainty, reason}

    case emit(state, packet) do
      {:ok, state} -> {:ok, %{state | partial?: state.partial? and kind != :speech_ended}}
      result -> result
    end
  end

  defp position(state, sample, confirmed) do
    case AudioTimeline.at(state.timeline, sample) do
      {:ok, position} when position.offset_us <= confirmed ->
        {position.offset_us, position.uncertainty_us, if(state.partial?, do: :partial_start)}

      {:ok, _future} ->
        {nil, nil, :clock_uncertain}

      {:error, reason} ->
        {nil, nil, reason}
    end
  end

  defp reset_and_pump(state, reason) do
    case reset(state, reason) do
      {:ok, state} -> pump(state)
      {:stop, state} -> {:stop, :normal, state}
    end
  end

  defp reset(state, reason, at \\ nil) do
    state = %{
      state
      | stream: Silero.new(),
        boundary: ActivityBoundary.new(),
        sample_origin: nil,
        partial?: true,
        clean_reuse_epoch?: false,
        silence_prefix_frames: 0,
        epoch: state.epoch + 1
    }

    emit(state, {:reset, state.epoch, reason, at || state.clock.()})
  end

  defp emit(state, packet) do
    if current?(state) and CaptureHandoff.offer(state.output, packet) == :ok,
      do: {:ok, state},
      else: {:stop, state}
  end

  defp current?(state) do
    stats = CaptureHandoff.stats(state.input)

    AttachmentLease.current?(state.attachment_lease) and SourcePort.current?(state.source_port) and
      stats.overflow == 0 and stats.invalid == 0 and
      CaptureHandoff.current?(state.input) and CaptureHandoff.current?(state.output)
  end

  defp discard(state, charge) do
    CaptureHandoff.release(state.input, charge, :discarded)
    {:stop, state}
  end

  defp discard_mailbox(handoff) do
    receive do
      {:vxpipe_diagnostic_capture, token, grant, _, _} = message
      when token == handoff.token and grant == handoff.grant ->
        CaptureHandoff.message(handoff, message)
        discard_mailbox(handoff)
    after
      0 -> :ok
    end
  end
end
