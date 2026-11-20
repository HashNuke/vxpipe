defmodule Vxpipe.CallEngine.Diagnostics.SampleClock do
  @moduledoc "Bounded mapping from admitted audio samples to one server receipt clock."

  @enforce_keys [:clock_id, :source_epoch, :sample_rate, :maximum_frames]
  @derive {Inspect, only: [:clock_id, :sample_rate, :maximum_frames]}
  defstruct [:clock_id, :source_epoch, :sample_rate, :maximum_frames, :last_input, frames: []]

  def new(clock_id, source_epoch, sample_rate, options \\ []) do
    maximum = Keyword.get(options, :maximum_frames, 256)

    if is_binary(clock_id) and byte_size(clock_id) in 1..128 and
         is_binary(source_epoch) and byte_size(source_epoch) in 1..256 and
         sample_rate in [8_000, 16_000, 48_000] and is_integer(maximum) and
         maximum in 1..1_024 do
      %__MODULE__{
        clock_id: clock_id,
        source_epoch: source_epoch,
        sample_rate: sample_rate,
        maximum_frames: maximum
      }
    else
      raise ArgumentError, "invalid diagnostic sample clock"
    end
  end

  def push(%__MODULE__{} = clock, input) do
    with :ok <- validate_input(clock, input),
         :ok <- validate_order(clock.last_input, input) do
      if clock.last_input == input do
        {:ok, clock, []}
      else
        notices = gap(clock.last_input, input)
        duration = div(input.sample_count * 1_000_000, clock.sample_rate)

        reversed? =
          clock.last_input != nil and
            input.received_offset_us - duration < clock.last_input.received_offset_us

        compressed_span =
          if reversed? and notices == [],
            do: input.received_offset_us - clock.last_input.received_offset_us,
            else: nil

        frame =
          input
          |> Map.put(:uncertainty_us, uncertainty(clock, input, notices))
          |> Map.put(:includes_start?, clock.last_input == nil)
          |> Map.put(:compressed_span_us, compressed_span)
          |> Map.put(:clock_uncertain?, reversed? and notices != [])

        frames = Enum.take([frame | clock.frames], clock.maximum_frames)
        {:ok, %{clock | last_input: input, frames: frames}, notices}
      end
    end
  end

  def at(%__MODULE__{} = clock, sample) when is_integer(sample) and sample >= 0 do
    frame =
      clock.frames
      |> Enum.reverse()
      |> Enum.find(fn frame ->
        (sample > frame.sample_timestamp or
           (frame.includes_start? and sample == frame.sample_timestamp)) and
          sample <= frame.sample_timestamp + frame.sample_count
      end)

    position(clock, frame, sample)
  end

  def at(%__MODULE__{}, _sample), do: {:error, :invalid_sample}
  def retained_frames(%__MODULE__{frames: frames}), do: length(frames)

  defp validate_input(clock, %{source_epoch: epoch}) when epoch != clock.source_epoch,
    do: {:error, :source_mismatch}

  defp validate_input(
         clock,
         %{
           sample_timestamp: timestamp,
           sample_count: count,
           sequence: sequence,
           received_offset_us: received,
           source_epoch: _epoch
         } = input
       )
       when map_size(input) == 5 and is_integer(timestamp) and
              timestamp in 0..9_223_372_036_854_775_807 and
              is_integer(count) and count > 0 and count <= clock.sample_rate and
              is_integer(sequence) and sequence in 0..9_223_372_036_854_775_807 and
              is_integer(received) and
              received >= 0 and received <= 604_800_000_000,
       do: :ok

  defp validate_input(_clock, _input), do: {:error, :invalid_frame}

  defp validate_order(nil, _input), do: :ok
  defp validate_order(input, input), do: :ok

  defp validate_order(last, input) do
    cond do
      input.sequence == last.sequence ->
        {:error, :conflicting_frame}

      input.sequence < last.sequence ->
        {:error, :out_of_order}

      input.sample_timestamp < last.sample_timestamp + last.sample_count ->
        {:error, :out_of_order}

      input.received_offset_us < last.received_offset_us ->
        {:error, :out_of_order}

      true ->
        :ok
    end
  end

  defp gap(nil, _input), do: []

  defp gap(last, input) do
    if input.sequence == last.sequence + 1 and
         input.sample_timestamp == last.sample_timestamp + last.sample_count,
       do: [],
       else: [:audio_gap]
  end

  defp uncertainty(%{last_input: nil}, _input, _notices), do: 1_000
  defp uncertainty(_clock, _input, [_notice]), do: 1_000

  defp uncertainty(clock, input, []) do
    duration = div(input.sample_count * 1_000_000, clock.sample_rate)
    1_000 + abs(input.received_offset_us - clock.last_input.received_offset_us - duration)
  end

  defp position(_clock, nil, _sample), do: {:error, :unobserved_audio}

  defp position(_clock, %{clock_uncertain?: true}, _sample), do: {:error, :clock_uncertain}

  defp position(clock, frame, sample) do
    trailing_samples = frame.sample_timestamp + frame.sample_count - sample

    trailing_us =
      case frame.compressed_span_us do
        nil -> div(trailing_samples * 1_000_000, clock.sample_rate)
        span -> div(trailing_samples * span, frame.sample_count)
      end

    offset = frame.received_offset_us - trailing_us

    if offset < 0 do
      {:error, :before_run}
    else
      {:ok,
       %{
         clock_id: clock.clock_id,
         source_epoch: clock.source_epoch,
         sample: sample,
         sample_rate: clock.sample_rate,
         offset_us: offset,
         uncertainty_us: frame.uncertainty_us
       }}
    end
  end
end
