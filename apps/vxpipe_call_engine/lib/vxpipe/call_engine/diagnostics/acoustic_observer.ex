defmodule Vxpipe.CallEngine.Diagnostics.AcousticObserver do
  @moduledoc "Passive boundary state over timestamped probability windows; emits no speech-control events."
  alias Vxpipe.CallEngine.Diagnostics.SampleClock
  alias Vxpipe.CallEngine.Speech.ActivityBoundary
  @enforce_keys [:clock, :boundary]
  @derive {Inspect, only: []}
  defstruct [:clock, :boundary, :last_probability, :last_processed_us]

  def new(clock_id, source_epoch, options \\ []),
    do: %__MODULE__{
      clock: SampleClock.new(clock_id, source_epoch, 16_000, options),
      boundary: ActivityBoundary.new()
    }

  def observe(
        %__MODULE__{} = observer,
        %{sample_count: 512, received_offset_us: received} = frame,
        probability,
        processed_us
      )
      when is_number(probability) and probability >= 0 and probability <= 1 and
             is_integer(received) and is_integer(processed_us) and processed_us >= received and
             processed_us <= 604_800_000_000 do
    cond do
      frame == observer.clock.last_input and probability != observer.last_probability ->
        {:error, :conflicting_frame}

      frame == observer.clock.last_input ->
        {:ok, observer, [], []}

      observer.last_processed_us != nil and processed_us < observer.last_processed_us ->
        {:error, :out_of_order}

      true ->
        advance(observer, frame, probability, processed_us)
    end
  end

  def observe(%__MODULE__{}, _frame, _probability, _processed_us),
    do: {:error, :invalid_observation}

  defp advance(observer, frame, probability, processed_us) do
    with {:ok, clock, notices} <- SampleClock.push(observer.clock, frame) do
      boundary =
        if observer.clock.last_input == nil or notices != [],
          do: %{ActivityBoundary.new() | samples: frame.sample_timestamp},
          else: observer.boundary

      {:ok, boundary, boundaries} = ActivityBoundary.push(boundary, probability)
      events = Enum.map(boundaries, &map_boundary(clock, &1, processed_us))

      {:ok,
       %{
         observer
         | clock: clock,
           boundary: boundary,
           last_probability: probability,
           last_processed_us: processed_us
       }, events, notices}
    end
  end

  defp map_boundary(clock, {kind, sample}, processed_us) do
    case SampleClock.at(clock, sample) do
      {:ok, position} -> {kind, Map.put(position, :confirmed_offset_us, processed_us)}
      {:error, reason} -> {:unmapped_boundary, kind, sample, reason}
    end
  end
end
