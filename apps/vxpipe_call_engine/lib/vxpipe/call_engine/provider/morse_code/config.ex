defmodule Vxpipe.CallEngine.Provider.MorseCode.Config do
  @moduledoc false

  @default_maximum_audio_bytes 8_388_608
  @default_maximum_text_bytes 256
  @default_maximum_utterance_ms 60_000
  @maximum_configured_audio_bytes 16_777_216
  @maximum_configured_text_bytes 4_096
  @sample_rates [8_000, 16_000, 24_000, 48_000]

  @enforce_keys [
    :amplitude,
    :detection_threshold,
    :end_gap_units,
    :frequency_hz,
    :frequency_tolerance_hz,
    :maximum_audio_bytes,
    :maximum_text_bytes,
    :maximum_utterance_ms,
    :sample_rate,
    :unit_duration_ms,
    :window_duration_ms
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          amplitude: pos_integer(),
          detection_threshold: pos_integer(),
          end_gap_units: pos_integer(),
          frequency_hz: pos_integer(),
          frequency_tolerance_hz: pos_integer(),
          maximum_audio_bytes: pos_integer(),
          maximum_text_bytes: pos_integer(),
          maximum_utterance_ms: pos_integer(),
          sample_rate: pos_integer(),
          unit_duration_ms: pos_integer(),
          window_duration_ms: pos_integer()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(options \\ [])

  def new(options) when is_list(options) do
    config = %__MODULE__{
      amplitude: Keyword.get(options, :amplitude, 4_096),
      detection_threshold: Keyword.get(options, :detection_threshold, 300),
      end_gap_units: Keyword.get(options, :end_gap_units, 14),
      frequency_hz: Keyword.get(options, :frequency_hz, 700),
      frequency_tolerance_hz: Keyword.get(options, :frequency_tolerance_hz, 100),
      maximum_audio_bytes:
        Keyword.get(options, :maximum_audio_bytes, @default_maximum_audio_bytes),
      maximum_text_bytes: Keyword.get(options, :maximum_text_bytes, @default_maximum_text_bytes),
      maximum_utterance_ms:
        Keyword.get(options, :maximum_utterance_ms, @default_maximum_utterance_ms),
      sample_rate: Keyword.get(options, :sample_rate, 16_000),
      unit_duration_ms: Keyword.get(options, :unit_duration_ms, 60),
      window_duration_ms: Keyword.get(options, :window_duration_ms, 10)
    }

    if valid?(config), do: {:ok, config}, else: {:error, :invalid_configuration}
  end

  def new(_options), do: {:error, :invalid_configuration}

  @doc "The configuration option keys this provider accepts."
  def option_keys, do: Map.keys(Map.from_struct(__MODULE__.__struct__()))

  defp valid?(config) do
    config.sample_rate in @sample_rates and
      integer_between?(config.unit_duration_ms, 20, 200) and
      integer_between?(config.window_duration_ms, 5, 20) and
      rem(config.unit_duration_ms, config.window_duration_ms) == 0 and
      rem(config.sample_rate * config.window_duration_ms, 1_000) == 0 and
      integer_between?(config.frequency_hz, 300, 2_000) and
      config.frequency_hz < div(config.sample_rate, 2) and
      integer_between?(config.frequency_tolerance_hz, 20, 250) and
      integer_between?(config.amplitude, 1, 8_191) and
      integer_between?(config.detection_threshold, 1, config.amplitude - 1) and
      integer_between?(config.end_gap_units, 8, 30) and
      integer_between?(config.maximum_text_bytes, 1, @maximum_configured_text_bytes) and
      integer_between?(config.maximum_audio_bytes, 1, @maximum_configured_audio_bytes) and
      integer_between?(config.maximum_utterance_ms, config.unit_duration_ms * 14, 300_000)
  end

  defp integer_between?(value, minimum, maximum) do
    is_integer(value) and value >= minimum and value <= maximum
  end
end
