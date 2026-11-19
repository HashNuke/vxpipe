defmodule Vxpipe.CallEngine.Diagnostics.SourceWorker do
  @moduledoc "Isolated benchmark-only source consumer; never emits speech-control events."
  use GenServer
  alias Vxpipe.CallEngine.Diagnostics.{AudioTimeline, CaptureHandoff, InferenceAdmission}
  alias Vxpipe.CallEngine.Speech.{ActivityBoundary, Silero}

  def child_spec(options),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary}

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def handoff(worker), do: GenServer.call(worker, :handoff)

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(options, :owner)
    output = Keyword.fetch!(options, :output)
    admission = Keyword.fetch!(options, :admission)

    capture_options =
      Keyword.take(options, [:projection, :maximum_count, :maximum_bytes])
      |> Keyword.put(:owner, owner)

    with true <- output.owner == owner and CaptureHandoff.current?(output),
         true <- is_struct(admission, InferenceAdmission) and Process.alive?(admission.runtime),
         {:ok, input} <- CaptureHandoff.new(self(), capture_options),
         true <- input.grant == output.grant and input.projection == output.projection do
      Enum.each([owner, output.receiver, admission.runtime], &Process.monitor/1)

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
         admission: admission,
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
  def handle_call(:handoff, _from, state), do: {:reply, state.input, state}

  @impl true
  def handle_info({:vxpipe_diagnostic_capture, _, _, _, _} = message, state) do
    case CaptureHandoff.message(state.input, message) do
      {:ok, packet, charge} -> pump(%{state | queue: :queue.in({packet, charge}, state.queue)})
      {:error, :revoked} -> {:stop, :normal, state}
      :error -> {:noreply, state}
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
    Process.cancel_timer(state.timer)

    if state.inference,
      do: CaptureHandoff.release(state.input, state.inference.charge, :discarded)

    Enum.each(:queue.to_list(state.queue), fn {_packet, charge} ->
      CaptureHandoff.release(state.input, charge, :discarded)
    end)

    discard_mailbox(state.input)
  end

  @impl true
  def format_status(status),
    do:
      status
      |> Map.put(:state, %{mode: :benchmark_only})
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

  defp process(state, {{:audio, frame}, charge}) do
    case AudioTimeline.push(state.timeline, frame) do
      {:ok, timeline, pcm, notices} ->
        state = %{state | timeline: timeline}

        case if(notices == [], do: {:ok, state}, else: reset(state, :audio_gap)) do
          {:ok, state} -> infer(state, pcm, charge)
          {:stop, state} -> discard(state, charge)
        end

      {:duplicate, _timeline} ->
        CaptureHandoff.release(state.input, charge, :processed)
        {:ok, state}

      {:error, :source_mismatch} ->
        discard(state, charge)

      {:error, _reason} ->
        CaptureHandoff.release(state.input, charge, :discarded)
        reset(state, :audio_gap)
    end
  end

  # Standalone acoustic state is independent of provider settlements.
  defp process(state, {{:reset, _epoch, :provider_turn_settled, _at}, charge}) do
    CaptureHandoff.release(state.input, charge, :processed)
    {:ok, state}
  end

  defp process(state, {{:provider_landmark, _, _, _, _, _} = packet, charge}) do
    CaptureHandoff.release(state.input, charge, :processed)
    emit(state, packet)
  end

  defp process(state, {_packet, charge}), do: discard(state, charge)

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
      {:ok, boundary, events} = ActivityBoundary.push(state.boundary, probability)

      case emit_boundaries(%{state | boundary: boundary}, events) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:stop, state} -> {:halt, {:stop, state}}
      end
    end)
  end

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

  defp reset(state, reason) do
    state = %{
      state
      | stream: Silero.new(),
        boundary: ActivityBoundary.new(),
        sample_origin: nil,
        partial?: true,
        epoch: state.epoch + 1
    }

    emit(state, {:reset, state.epoch, reason, state.clock.()})
  end

  defp emit(state, packet) do
    if current?(state) and CaptureHandoff.offer(state.output, packet) == :ok,
      do: {:ok, state},
      else: {:stop, state}
  end

  defp current?(state),
    do: CaptureHandoff.current?(state.input) and CaptureHandoff.current?(state.output)

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
