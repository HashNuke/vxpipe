defmodule Vxpipe.CallEngine.Diagnostics.AudioTimeline do
  @moduledoc "Bounded accepted-audio normalization and receipt-clock mapping, outside call control."
  alias Vxpipe.CallEngine.Diagnostics.{CapturePacket, SampleClock}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Speech.STTActivityPCM

  @identity [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :connection_id,
    :track_id,
    :sample_rate
  ]
  @enforce_keys [:clock, :source_epoch, :origin_us]
  @derive {Inspect, only: []}
  defstruct [:clock, :source_epoch, :origin_us, :source_clock, :identity, :digest, sequence: 0]

  def new(clock_id, source_id, source_epoch, origin_us, options \\ [])
      when is_reference(source_epoch) and is_integer(origin_us) do
    %__MODULE__{
      clock: SampleClock.new(clock_id, source_id, 16_000, options),
      source_epoch: source_epoch,
      origin_us: origin_us
    }
  end

  def push(%__MODULE__{} = timeline, %AudioFrame{} = frame) do
    with {:ok, _charge} <- CapturePacket.charge({:audio, frame}),
         true <- same_source?(timeline, frame),
         {:audio, frame} <- CapturePacket.copy({:audio, frame}),
         {:ok, pcm, timestamp} <- STTActivityPCM.normalize(frame) do
      accept(timeline, frame, pcm, timestamp)
    else
      false -> {:error, :source_mismatch}
      _ -> {:error, :unsupported_audio}
    end
  end

  def push(_timeline, _frame), do: {:error, :unsupported_audio}

  def at(%__MODULE__{source_clock: nil}, _sample), do: {:error, :unobserved_audio}

  def at(%__MODULE__{} = timeline, sample) do
    with {:ok, position} <- SampleClock.at(timeline.clock, sample) do
      # At most one source and one output sample period of conversion uncertainty.
      conversion_us =
        div(1_000_000 + timeline.source_clock.sample_rate - 1, timeline.source_clock.sample_rate) +
          63

      {:ok, %{position | uncertainty_us: position.uncertainty_us + conversion_us}}
    end
  end

  defp same_source?(timeline, frame),
    do:
      frame.source_epoch == timeline.source_epoch and
        (timeline.identity == nil or timeline.identity == Map.take(frame, @identity))

  defp accept(timeline, frame, pcm, timestamp) do
    clock =
      timeline.source_clock ||
        SampleClock.new(timeline.clock.clock_id, timeline.clock.source_epoch, frame.sample_rate,
          maximum_frames: 1
        )

    metadata = %{
      source_epoch: clock.source_epoch,
      sample_timestamp: frame.timestamp,
      sample_count: div(byte_size(frame.payload), 2),
      sequence: frame.sequence_number,
      received_offset_us: frame.received_at * 1_000 - timeline.origin_us
    }

    digest = :crypto.hash(:sha256, frame.payload)

    cond do
      clock.last_input == metadata and timeline.digest == digest ->
        {:duplicate, timeline}

      clock.last_input == metadata ->
        {:error, :conflicting_frame}

      true ->
        with {:ok, source_clock, notices} <- SampleClock.push(clock, metadata) do
          timeline = %{
            timeline
            | source_clock: source_clock,
              identity: Map.take(frame, @identity),
              digest: digest
          }

          normalized(timeline, pcm, timestamp, metadata.received_offset_us, notices)
        end
    end
  end

  defp normalized(timeline, pcm, timestamp, received, notices) do
    clock =
      if notices == [], do: timeline.clock, else: %{timeline.clock | frames: []}

    if pcm == "" do
      {:ok, %{timeline | clock: clock}, "", notices}
    else
      metadata = %{
        source_epoch: clock.source_epoch,
        sample_timestamp: timestamp,
        sample_count: div(byte_size(pcm), 2),
        sequence: timeline.sequence,
        received_offset_us: received
      }

      with {:ok, clock, normalized_notices} <- SampleClock.push(clock, metadata) do
        clock = preserve_source_uncertainty(clock, timeline.source_clock)

        {:ok, %{timeline | clock: clock, sequence: timeline.sequence + 1}, :binary.copy(pcm),
         Enum.uniq(notices ++ normalized_notices)}
      end
    end
  end

  defp preserve_source_uncertainty(clock, source_clock) do
    [frame | rest] = clock.frames
    [source] = source_clock.frames

    frame = %{
      frame
      | clock_uncertain?: frame.clock_uncertain? or source.clock_uncertain?,
        uncertainty_us: max(frame.uncertainty_us, source.uncertainty_us)
    }

    %{clock | frames: [frame | rest]}
  end
end
