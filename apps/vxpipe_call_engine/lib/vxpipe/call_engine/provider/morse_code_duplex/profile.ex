defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.Profile do
  @moduledoc """
  Pure configuration for the Morse duplex provider: the public descriptor facts
  and the raw PCM settings the session derives from them.
  """

  alias Vxpipe.CallEngine.Provider.MorseCode.Config
  alias Vxpipe.CallEngine.Speech.Descriptor

  @spec configure(keyword()) :: {:ok, Descriptor.t()} | {:error, :invalid_configuration}
  def configure(options) do
    allowed = Config.option_keys() ++ [:output_transcript, :yield?, :clock]

    with true <- is_list(options) and Keyword.keyword?(options),
         true <- length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))),
         true <- Enum.all?(Keyword.keys(options), &(&1 in allowed)),
         {output_transcript, rest} = Keyword.pop(options, :output_transcript, true),
         true <- is_boolean(output_transcript),
         {yield?, rest} = Keyword.pop(rest, :yield?, true),
         true <- is_boolean(yield?),
         {clock, rest} = Keyword.pop(rest, :clock, :realtime),
         true <- clock in [:realtime, :manual],
         {:ok, config} <- Config.new(rest),
         true <- config.amplitude >= 2 do
      Descriptor.new(
        kind: :sts,
        settings:
          config
          |> Map.from_struct()
          |> Map.put(:yield?, yield?)
          |> Map.put(:clock, clock),
        input_format: format(config),
        format: format(config),
        usage_identity: %{
          provider: :morse_code_duplex,
          model: :morse_code,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: :inferred_gap,
        speech_start?: true,
        response_start?: true,
        turn_control: "provider",
        turn_control_supported: ["provider"],
        input_transcript?: true,
        output_transcript?: output_transcript,
        output_settlement: :transcript_end,
        history_reconciliation?: false,
        output_shape: :continuous,
        barge_in: :provider,
        continuity: :history_reseed,
        tool_cancellation?: false,
        hold: :mute
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @spec format(Config.t()) :: map()
  def format(config) do
    %{
      encoding: :linear16,
      container: :raw,
      sample_rate: config.sample_rate,
      channels: 1,
      byte_order: :little,
      signed?: true
    }
  end

  @spec segmenter_options(Config.t()) :: keyword()
  def segmenter_options(config) do
    [
      sample_rate: config.sample_rate,
      silence_floor: 0,
      activation_threshold: max(div(config.amplitude, 2), 1),
      deactivation_threshold: max(div(config.amplitude, 4), 0)
    ]
  end
end
