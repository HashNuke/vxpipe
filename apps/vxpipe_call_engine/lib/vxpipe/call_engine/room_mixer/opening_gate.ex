defmodule Vxpipe.CallEngine.RoomMixer.OpeningGate do
  @moduledoc false

  @enforce_keys [:clock, :clock_origin_ms, :sample_rate, :minimum_timestamp]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec new(keyword(), integer(), pos_integer()) :: t()
  def new(options, clock_origin_ms, sample_rate) do
    %__MODULE__{
      clock: Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end),
      clock_origin_ms: clock_origin_ms,
      sample_rate: sample_rate,
      minimum_timestamp:
        if(Keyword.get(options, :awaiting_opening_audio, false), do: nil, else: 0)
    }
  end

  @spec open(t()) :: t()
  def open(%__MODULE__{minimum_timestamp: nil} = gate) do
    elapsed_ms = max(gate.clock.() - gate.clock_origin_ms, 0)
    %{gate | minimum_timestamp: div(elapsed_ms * gate.sample_rate + 999, 1_000)}
  end

  def open(%__MODULE__{} = gate), do: gate

  @spec admits?(t(), non_neg_integer()) :: boolean()
  def admits?(%__MODULE__{minimum_timestamp: nil}, _timestamp), do: false

  def admits?(%__MODULE__{minimum_timestamp: minimum}, timestamp),
    do: is_integer(timestamp) and timestamp >= minimum

  @spec awaiting?(t()) :: boolean()
  def awaiting?(%__MODULE__{minimum_timestamp: nil}), do: true
  def awaiting?(%__MODULE__{}), do: false

  @spec admits_recording?(t(), map()) :: boolean()
  def admits_recording?(%__MODULE__{minimum_timestamp: nil} = _gate, %{origin: :room} = frame),
    do: is_integer(Map.get(frame, :timestamp)) and Map.get(frame, :timestamp) >= 0

  def admits_recording?(%__MODULE__{} = gate, %{timestamp: timestamp}),
    do: admits?(gate, timestamp)

  def admits_recording?(%__MODULE__{} = gate, timestamp) when is_integer(timestamp),
    do: admits?(gate, timestamp)
end
