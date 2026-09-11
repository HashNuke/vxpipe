defmodule Vxpipe.CallEngine.Usage.Observation do
  @moduledoc "One immutable, call-scoped usage or cost observation."

  alias Vxpipe.CallEngine.Usage.{Attribution, Measurement, ProviderContext}

  @capabilities [:model_inference, :speech_to_text, :text_to_speech, :tool, :telephony]
  @outcomes [:in_progress, :succeeded, :failed, :cancelled, :unknown]

  @enforce_keys [
    :id,
    :tenant_id,
    :call_id,
    :attempt_id,
    :capability,
    :provider,
    :attribution,
    :outcome,
    :observed_at
  ]

  defstruct @enforce_keys ++ [delivery_id: nil, source_sequence: nil, measurement: nil]

  @type capability ::
          :model_inference | :speech_to_text | :text_to_speech | :tool | :telephony

  @type outcome :: :in_progress | :succeeded | :failed | :cancelled | :unknown

  @type t :: %__MODULE__{
          id: String.t(),
          delivery_id: String.t() | nil,
          source_sequence: non_neg_integer() | nil,
          tenant_id: String.t(),
          call_id: String.t(),
          attempt_id: String.t(),
          capability: capability(),
          provider: ProviderContext.t(),
          attribution: Attribution.t(),
          measurement: Measurement.t() | nil,
          outcome: outcome(),
          observed_at: DateTime.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_observation}
  def new(options) when is_list(options) do
    defaults = [delivery_id: nil, source_sequence: nil, measurement: nil]

    required = [
      :id,
      :tenant_id,
      :call_id,
      :attempt_id,
      :capability,
      :provider,
      :attribution,
      :outcome,
      :observed_at
    ]

    with {:ok, options} <- Keyword.validate(options, required ++ defaults),
         true <-
           Enum.all?([:id, :tenant_id, :call_id, :attempt_id], fn field ->
             valid_identifier?(Keyword.get(options, field))
           end),
         true <- valid_optional_identifier?(Keyword.get(options, :delivery_id)),
         true <- valid_sequence?(Keyword.get(options, :source_sequence)),
         capability when capability in @capabilities <- Keyword.get(options, :capability),
         %ProviderContext{} <- Keyword.get(options, :provider),
         %Attribution{} <- Keyword.get(options, :attribution),
         true <- valid_measurement?(Keyword.get(options, :measurement)),
         outcome when outcome in @outcomes <- Keyword.get(options, :outcome),
         %DateTime{} <- Keyword.get(options, :observed_at) do
      {:ok, struct!(__MODULE__, options)}
    else
      _invalid -> {:error, :invalid_observation}
    end
  end

  def new(_options), do: {:error, :invalid_observation}

  defp valid_identifier?(value) do
    is_binary(value) and String.trim(value) != "" and byte_size(value) <= 128
  end

  defp valid_optional_identifier?(nil), do: true
  defp valid_optional_identifier?(value), do: valid_identifier?(value)

  defp valid_sequence?(nil), do: true
  defp valid_sequence?(value), do: is_integer(value) and value >= 0

  defp valid_measurement?(nil), do: true
  defp valid_measurement?(%Measurement{}), do: true
  defp valid_measurement?(_measurement), do: false
end
