defmodule Vxpipe.CallEngine.Speech.Descriptor do
  @moduledoc "Validated public settings and evidence supplied by a speech provider."

  @enforce_keys [:kind, :settings, :format, :usage_identity, :readiness, :endpointing]
  @derive {Inspect,
           only: [:kind, :format, :readiness, :endpointing, :speech_start?, :eager_end?, :resume?]}
  defstruct @enforce_keys ++
              [
                input_format: nil,
                finite_input?: false,
                speech_start?: false,
                response_start?: false,
                eager_end?: false,
                resume?: false,
                cache_identity: nil,
                turn_control: nil,
                turn_control_supported: [],
                input_transcript?: false,
                output_transcript?: false,
                output_settlement: nil,
                history_reconciliation?: false
              ]

  @fields @enforce_keys ++
            [
              :input_format,
              :finite_input?,
              :speech_start?,
              :response_start?,
              :eager_end?,
              :resume?,
              :cache_identity,
              :turn_control,
              :turn_control_supported,
              :input_transcript?,
              :output_transcript?,
              :output_settlement,
              :history_reconciliation?
            ]
  @identity_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._\/-]*\z/

  @type t :: %__MODULE__{
          kind: :stt | :tts | :sts,
          settings: map(),
          format: map(),
          input_format: map() | nil,
          finite_input?: boolean(),
          usage_identity: map(),
          readiness: :initialized | :provider_acknowledged,
          endpointing: :provider_semantic | :provider_gap | :external | :none,
          speech_start?: boolean(),
          response_start?: boolean(),
          eager_end?: boolean(),
          resume?: boolean(),
          cache_identity: binary() | nil,
          turn_control: binary() | nil,
          turn_control_supported: [binary()],
          input_transcript?: boolean(),
          output_transcript?: boolean(),
          output_settlement: nil | :transcript_end | :generation_boundary,
          history_reconciliation?: boolean()
        }

  @doc "Build public metadata. Provider-specific settings remain the provider's validation responsibility."
  def new(fields) when is_list(fields) do
    if Keyword.keyword?(fields) and Enum.all?(Keyword.keys(fields), &(&1 in @fields)) and
         length(Keyword.keys(fields)) == length(Enum.uniq(Keyword.keys(fields))) do
      descriptor = struct(__MODULE__, fields)
      with :ok <- validate(descriptor), do: {:ok, descriptor}
    else
      {:error, :invalid_descriptor}
    end
  end

  def new(_fields), do: {:error, :invalid_descriptor}

  @doc "Validate again at the engine boundary, including directly constructed descriptors."
  def validate(%__MODULE__{} = descriptor) do
    if Enum.sort(Map.keys(descriptor)) == Enum.sort([:__struct__ | @fields]) and
         is_map(descriptor.settings) and
         valid_format?(descriptor.format) and valid_identity?(descriptor.usage_identity) and
         descriptor.readiness in [:initialized, :provider_acknowledged] and
         descriptor.endpointing in [:provider_semantic, :provider_gap, :external, :none] and
         is_boolean(descriptor.speech_start?) and is_boolean(descriptor.eager_end?) and
         is_boolean(descriptor.response_start?) and
         (not descriptor.response_start? or descriptor.kind == :sts) and
         is_boolean(descriptor.resume?) and
         is_boolean(descriptor.finite_input?) and
         (not descriptor.finite_input? or descriptor.kind == :stt) and
         (not descriptor.eager_end? or
            descriptor.endpointing in [:provider_semantic, :provider_gap]) and
         valid_kind?(descriptor) do
      :ok
    else
      {:error, :invalid_descriptor}
    end
  end

  def validate(_descriptor), do: {:error, :invalid_descriptor}

  @doc "Validate an STT descriptor for a conversation that requires end-of-turn authority."
  def validate_conversational_stt(%__MODULE__{} = descriptor) do
    with :ok <- validate(descriptor),
         true <- descriptor.kind == :stt,
         true <- descriptor.endpointing in [:provider_semantic, :provider_gap],
         true <- descriptor.speech_start? do
      :ok
    else
      _invalid -> {:error, :invalid_descriptor}
    end
  end

  def validate_conversational_stt(_descriptor), do: {:error, :invalid_descriptor}

  defp valid_kind?(%{kind: :stt, cache_identity: nil, input_format: nil}), do: true

  defp valid_kind?(%{kind: :sts, cache_identity: nil} = descriptor),
    do:
      descriptor.turn_control in ["provider", "external", "hybrid"] and
        valid_format?(descriptor.input_format) and
        descriptor.input_format.encoding == :linear16 and
        descriptor.format.encoding == :linear16 and
        is_list(descriptor.turn_control_supported) and
        Enum.all?(descriptor.turn_control_supported, &(&1 in ["provider", "external", "hybrid"])) and
        length(descriptor.turn_control_supported) ==
          length(Enum.uniq(descriptor.turn_control_supported)) and
        descriptor.turn_control in descriptor.turn_control_supported and
        is_boolean(descriptor.input_transcript?) and is_boolean(descriptor.output_transcript?) and
        descriptor.output_settlement in [:transcript_end, :generation_boundary] and
        is_boolean(descriptor.history_reconciliation?) and valid_sts_controller?(descriptor)

  defp valid_kind?(%{kind: :tts, cache_identity: identity, input_format: nil} = descriptor),
    do:
      is_binary(identity) and byte_size(identity) == 32 and
        descriptor.format.encoding == :linear16 and descriptor.endpointing == :none and
        not descriptor.speech_start? and not descriptor.eager_end? and not descriptor.resume?

  defp valid_kind?(_descriptor), do: false

  defp valid_sts_controller?(%{turn_control: "external", endpointing: :external}), do: true

  defp valid_sts_controller?(%{turn_control: mode, endpointing: evidence, speech_start?: true})
       when mode in ["provider", "hybrid"] and evidence in [:provider_gap, :provider_semantic],
       do: true

  defp valid_sts_controller?(_descriptor), do: false

  defp valid_format?(
         %{
           encoding: :linear16,
           container: :raw,
           channels: 1,
           byte_order: :little,
           signed?: true,
           sample_rate: rate
         } = format
       ),
       do: map_size(format) == 6 and is_integer(rate) and rate > 0

  defp valid_format?(
         %{encoding: :opus, container: :raw, channels: 1, sample_rate: rate} = format
       ),
       do: map_size(format) == 4 and is_integer(rate) and rate > 0

  defp valid_format?(_format), do: false

  defp valid_identity?(%{provider: provider, model: model, provenance: provenance} = identity),
    do:
      map_size(identity) == 3 and valid_label?(provider) and valid_label?(model) and
        provenance in [:locally_measured, :provider_reported]

  defp valid_identity?(_identity), do: false

  defp valid_label?(value) when is_atom(value) and value not in [nil, true, false],
    do: valid_label?(Atom.to_string(value))

  defp valid_label?(value) when is_binary(value),
    do:
      byte_size(value) in 1..256 and String.valid?(value) and
        Regex.match?(@identity_pattern, value)

  defp valid_label?(_value), do: false
end
