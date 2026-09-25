defmodule Vxpipe.CallEngine.Speech.Duplex.OutputSegmenter do
  @moduledoc """
  Segments a GPT-Live-style continuous output stream into admitted output turns.

  The provider streams output audio with no turn, timing or completion events.
  An energy gate over the output PCM marks burst boundaries; it never changes the
  audio it forwards. A pre-roll of recent sub-threshold audio is replayed at the
  start of each burst so quiet word onsets are not clipped, and pauses shorter
  than the gap stay inside the burst. Silence between bursts is not forwarded.

  The module is pure and clock-free: all durations are audio time. The adapter
  maps `{:open, ref}`/`{:audio, ref, pcm}`/`{:close, ref}` onto
  `Session.admit_output/2`, the credited PCM path and `:output_completed`.

  Transcript fragments are aligned to bursts with `fragment/2`. The first
  aligned fragment fixes the offset between the provider timeline and the output
  audio; later fragments are reported relative to that output. A fragment whose
  audio already played attaches to its earlier output. A fragment with no
  matching audio after `fragment_timeout_ms` of further output is dropped and
  counted, never published as spoken text.
  """

  @default_sample_rate 24_000
  @default_frame_ms 20
  @default_gap_ms 800
  @default_pre_roll_ms 300
  @default_buffer_ms 2_000
  @default_fragment_timeout_ms 3_000
  @default_silence_floor 0
  @default_activation_offset 1_000
  @default_deactivation_offset 300
  @maximum_retired_outputs 8
  @maximum_sample 32_768

  @enforce_keys [:config]
  defstruct [
    :config,
    :phase,
    :pending,
    :pre_roll,
    :silence_frames,
    :output_ref,
    :output_order,
    :outputs,
    :burst_ms,
    :buffer,
    :produced_ms,
    :held,
    :dropped
  ]

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(options \\ [])

  def new(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))),
         true <- Enum.all?(Keyword.keys(options), &(&1 in allowed_options())),
         {:ok, config} <- config(options) do
      {:ok, initial_state(config)}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  @doc "Push provider output PCM; returns forwarded events or an explicit overflow."
  @spec push_pcm(t(), binary()) :: {t(), [term()]} | {:error, :buffer_overflow, t()}
  def push_pcm(%__MODULE__{} = state, pcm) when is_binary(pcm) do
    state = %{state | pending: state.pending <> pcm}
    {frames, pending} = split_frames(state.pending, state.config.frame_bytes)
    state = %{state | pending: pending}

    case process_frames(state, frames) do
      {:error, :buffer_overflow, state} ->
        {:error, :buffer_overflow, state}

      {state, events} ->
        {state, results} = check_held(state)
        {state, events ++ results}
    end
  end

  @doc "Confirm output admission and flush any buffered burst audio."
  @spec admitted(t(), reference()) :: {t(), [term()]}
  def admitted(%__MODULE__{phase: :awaiting, output_ref: ref} = state, ref),
    do: {%{state | phase: :open, buffer: <<>>}, [{:audio, ref, state.buffer}]}

  def admitted(%__MODULE__{} = state, _ref), do: {state, []}

  @doc "Align one provider output transcript fragment to an admitted output."
  @spec fragment(t(), map()) :: {t(), [term()]}
  def fragment(%__MODULE__{} = state, fragment) do
    case normalize_fragment(fragment) do
      {:ok, text, start_ms, end_ms} ->
        case align(state, text, start_ms, end_ms) do
          {:ok, state, result} ->
            {state, [result]}

          :pending ->
            held = [
              %{text: text, start_ms: start_ms, end_ms: end_ms, held_at: state.produced_ms}
              | state.held
            ]

            check_held(%{state | held: held})
        end

      :error ->
        {state, []}
    end
  end

  @doc "Close an open burst and drop any unmatchable fragments."
  @spec finish(t()) :: {t(), [term()]}
  def finish(%__MODULE__{} = state) do
    {state, events} =
      case state.phase do
        :closed -> {state, []}
        _open -> close_burst(state)
      end

    dropped = Enum.map(state.held, &{:dropped, &1.text})
    {%{state | held: [], dropped: state.dropped + length(state.held)}, events ++ dropped}
  end

  @spec burst?(t()) :: boolean()
  def burst?(%__MODULE__{phase: :closed}), do: false
  def burst?(%__MODULE__{}), do: true

  @spec dropped(t()) :: non_neg_integer()
  def dropped(%__MODULE__{dropped: dropped}), do: dropped

  defp initial_state(config) do
    %__MODULE__{
      config: config,
      phase: :closed,
      pending: <<>>,
      pre_roll: [],
      silence_frames: 0,
      output_ref: nil,
      output_order: [],
      outputs: %{},
      burst_ms: 0,
      buffer: <<>>,
      produced_ms: 0,
      held: [],
      dropped: 0
    }
  end

  defp allowed_options do
    [
      :sample_rate,
      :frame_ms,
      :gap_ms,
      :pre_roll_ms,
      :buffer_ms,
      :fragment_timeout_ms,
      :silence_floor,
      :activation_threshold,
      :deactivation_threshold
    ]
  end

  defp config(options) do
    sample_rate = Keyword.get(options, :sample_rate, @default_sample_rate)
    frame_ms = Keyword.get(options, :frame_ms, @default_frame_ms)
    gap_ms = Keyword.get(options, :gap_ms, @default_gap_ms)
    pre_roll_ms = Keyword.get(options, :pre_roll_ms, @default_pre_roll_ms)
    buffer_ms = Keyword.get(options, :buffer_ms, @default_buffer_ms)
    fragment_timeout_ms = Keyword.get(options, :fragment_timeout_ms, @default_fragment_timeout_ms)
    silence_floor = Keyword.get(options, :silence_floor, @default_silence_floor)

    activation =
      Keyword.get(options, :activation_threshold, silence_floor + @default_activation_offset)

    deactivation =
      Keyword.get(options, :deactivation_threshold, silence_floor + @default_deactivation_offset)

    with true <- is_integer(sample_rate) and sample_rate > 0,
         true <- is_integer(frame_ms) and frame_ms > 0,
         true <- is_integer(gap_ms) and gap_ms > 0,
         true <- is_integer(pre_roll_ms) and pre_roll_ms >= 0,
         true <- is_integer(buffer_ms) and buffer_ms > 0,
         true <- is_integer(fragment_timeout_ms) and fragment_timeout_ms > 0,
         true <- is_integer(silence_floor) and silence_floor in 0..@maximum_sample,
         true <- is_integer(activation) and activation > deactivation,
         true <- is_integer(deactivation) and deactivation >= silence_floor,
         true <- activation <= @maximum_sample + 1,
         frame_bytes = div(sample_rate * frame_ms, 1_000) * 2,
         true <- frame_bytes > 0 do
      {:ok,
       %{
         sample_rate: sample_rate,
         frame_ms: frame_ms,
         frame_bytes: frame_bytes,
         gap_ms: gap_ms,
         pre_roll_frames: div(pre_roll_ms, frame_ms),
         buffer_bytes: div(buffer_ms * sample_rate, 1_000) * 2,
         fragment_timeout_ms: fragment_timeout_ms,
         silence_floor: silence_floor,
         activation_threshold: activation,
         deactivation_threshold: deactivation
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  defp split_frames(pending, frame_bytes) when byte_size(pending) < frame_bytes, do: {[], pending}

  defp split_frames(pending, frame_bytes) do
    <<frame::binary-size(frame_bytes), rest::binary>> = pending
    {frames, rest} = split_frames(rest, frame_bytes)
    {[frame | frames], rest}
  end

  defp process_frames(state, []), do: {state, []}

  defp process_frames(state, [frame | rest]) do
    case apply_frame(state, frame) do
      {:error, :buffer_overflow, state} ->
        {:error, :buffer_overflow, state}

      {state, events} ->
        {state, more} = process_frames(state, rest)
        {state, events ++ more}
    end
  end

  defp apply_frame(%{phase: :closed} = state, frame) do
    if active?(state, frame) do
      open_burst(state, frame)
    else
      {%{state | pre_roll: retain(state.pre_roll, frame, state.config.pre_roll_frames)}, []}
    end
  end

  defp apply_frame(%{phase: :awaiting} = state, frame) do
    state = %{
      state
      | buffer: state.buffer <> frame,
        burst_ms: state.burst_ms + state.config.frame_ms,
        produced_ms: state.produced_ms + state.config.frame_ms
    }

    if byte_size(state.buffer) > state.config.buffer_bytes do
      {:error, :buffer_overflow, state}
    else
      state = count_silence(state, frame)

      if silence_gap_reached?(state) do
        close_burst(state)
      else
        {state, []}
      end
    end
  end

  defp apply_frame(%{phase: :open} = state, frame) do
    ref = state.output_ref
    state = %{state | burst_ms: state.burst_ms + state.config.frame_ms}
    state = %{state | produced_ms: state.produced_ms + state.config.frame_ms}
    state = update_output_duration(state, ref, state.burst_ms)
    state = count_silence(state, frame)

    if silence_gap_reached?(state) do
      {state, closed} = close_burst(state)
      {state, [{:audio, ref, frame} | closed]}
    else
      {state, [{:audio, ref, frame}]}
    end
  end

  defp open_burst(state, frame) do
    ref = make_ref()
    pre_roll = IO.iodata_to_binary(Enum.reverse(state.pre_roll))

    outputs = Map.put(state.outputs, ref, %{base_ms: nil, duration_ms: 0})
    order = Enum.take([ref | state.output_order], @maximum_retired_outputs)

    state = %{
      state
      | phase: :awaiting,
        output_ref: ref,
        output_order: order,
        outputs: outputs,
        pre_roll: [],
        burst_ms: state.config.frame_ms,
        buffer: pre_roll <> frame,
        produced_ms: state.produced_ms + state.config.frame_ms,
        silence_frames: silence_frames(state, frame)
    }

    if byte_size(state.buffer) > state.config.buffer_bytes do
      {:error, :buffer_overflow, state}
    else
      {state, [{:open, ref}]}
    end
  end

  defp close_burst(%{phase: :closed} = state), do: {state, []}

  defp close_burst(state) do
    ref = state.output_ref
    state = update_output_duration(state, ref, state.burst_ms)

    state = %{
      state
      | phase: :closed,
        output_ref: nil,
        burst_ms: 0,
        buffer: <<>>,
        silence_frames: 0
    }

    {state, [{:close, ref}]}
  end

  defp count_silence(state, frame) do
    if silent?(state, frame),
      do: %{state | silence_frames: state.silence_frames + 1},
      else: %{state | silence_frames: 0}
  end

  defp silence_frames(state, frame), do: if(silent?(state, frame), do: 1, else: 0)

  defp silence_gap_reached?(state),
    do: state.silence_frames * state.config.frame_ms >= state.config.gap_ms

  defp update_output_duration(state, ref, duration_ms) do
    outputs =
      Map.update(
        state.outputs,
        ref,
        %{base_ms: nil, duration_ms: duration_ms},
        &Map.put(&1, :duration_ms, duration_ms)
      )

    %{state | outputs: outputs}
  end

  defp align(state, text, start_ms, end_ms) do
    case current_output(state) do
      %{ref: ref, base_ms: nil} ->
        outputs =
          Map.update(
            state.outputs,
            ref,
            %{base_ms: start_ms, duration_ms: 0},
            &Map.put(&1, :base_ms, start_ms)
          )

        {:ok, %{state | outputs: outputs}, {:transcript, ref, text, 0, end_ms - start_ms}}

      _other ->
        case find_output(state, start_ms) do
          {:ok, ref, base_ms} ->
            {:ok, state, {:transcript, ref, text, start_ms - base_ms, end_ms - base_ms}}

          :none ->
            :pending
        end
    end
  end

  defp current_output(%{output_ref: nil}), do: nil

  defp current_output(state) do
    case Map.fetch(state.outputs, state.output_ref) do
      {:ok, output} -> Map.put(output, :ref, state.output_ref)
      :error -> nil
    end
  end

  defp find_output(state, start_ms) do
    Enum.find_value(state.output_order, :none, fn ref ->
      case Map.fetch(state.outputs, ref) do
        {:ok, %{base_ms: base_ms} = output} when is_integer(base_ms) ->
          if start_ms >= base_ms and start_ms <= base_ms + output.duration_ms,
            do: {:ok, ref, base_ms},
            else: nil

        _other ->
          nil
      end
    end)
  end

  defp check_held(state) do
    {results, held} =
      Enum.reduce(state.held, {[], []}, fn held, {results, kept} ->
        case held_match(state, held) do
          {:ok, result} -> {[result | results], kept}
          :drop -> {[{:dropped, held.text} | results], kept}
          :keep -> {results, [held | kept]}
        end
      end)

    dropped = state.dropped + Enum.count(results, &match?({:dropped, _}, &1))
    {%{state | held: Enum.reverse(held), dropped: dropped}, Enum.reverse(results)}
  end

  defp held_match(state, held) do
    case held_output(state, held.start_ms) do
      {:ok, ref, base_ms} ->
        {:ok, {:transcript, ref, held.text, held.start_ms - base_ms, held.end_ms - base_ms}}

      :none ->
        if state.produced_ms - held.held_at >= state.config.fragment_timeout_ms,
          do: :drop,
          else: :keep
    end
  end

  defp held_output(state, start_ms) do
    case current_output(state) do
      %{ref: ref, base_ms: nil} -> {:ok, ref, start_ms}
      _other -> find_output(state, start_ms)
    end
  end

  defp active?(state, frame), do: energy(frame) > state.config.activation_threshold
  defp silent?(state, frame), do: energy(frame) <= state.config.deactivation_threshold

  defp energy(frame) do
    for <<sample::signed-little-16 <- frame>>, reduce: 0 do
      acc -> max(acc, abs(sample))
    end
  end

  defp retain(_pre_roll, _frame, 0), do: []
  defp retain(pre_roll, frame, limit), do: Enum.take([frame | pre_roll], limit)

  defp normalize_fragment(%{text: text, start_ms: start_ms, end_ms: end_ms})
       when is_binary(text) and is_integer(start_ms) and is_integer(end_ms) and start_ms >= 0 and
              end_ms >= start_ms,
       do: {:ok, text, start_ms, end_ms}

  defp normalize_fragment(_fragment), do: :error
end
