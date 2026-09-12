defmodule Vxpipe.Calls.BillingLookupRequest do
  @moduledoc "Payload-free provider-operation evidence presented to a billing lookup port."

  alias Vxpipe.CallEngine.Usage.{Attribution, Observation, ProviderContext}

  @capabilities [:model_inference, :speech_to_text, :text_to_speech, :tool, :telephony]
  @outcomes [:in_progress, :succeeded, :failed, :cancelled, :unknown]

  @derive {Inspect, only: [:tenant_key, :call_id, :attempt_id, :capability, :provider, :outcome]}
  @enforce_keys [
    :tenant_key,
    :call_id,
    :attempt_id,
    :capability,
    :provider,
    :attribution,
    :outcome
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_key: String.t(),
          call_id: String.t(),
          attempt_id: String.t(),
          capability: Observation.capability(),
          provider: ProviderContext.t(),
          attribution: Attribution.t(),
          outcome: Observation.outcome()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_billing_lookup_request}
  def new(options) when is_list(options) do
    with {:ok, options} <- Keyword.validate(options, @enforce_keys),
         true <-
           Enum.all?(
             [:tenant_key, :call_id, :attempt_id],
             &valid_id?(Keyword.fetch!(options, &1))
           ),
         capability when capability in @capabilities <- Keyword.fetch!(options, :capability),
         %ProviderContext{} = provider <- Keyword.fetch!(options, :provider),
         true <- external_reference?(provider),
         %Attribution{} <- Keyword.fetch!(options, :attribution),
         outcome when outcome in @outcomes <- Keyword.fetch!(options, :outcome) do
      {:ok, struct!(__MODULE__, options)}
    else
      _invalid -> {:error, :invalid_billing_lookup_request}
    end
  end

  def new(_options), do: {:error, :invalid_billing_lookup_request}

  defp valid_id?(value), do: is_binary(value) and value != "" and byte_size(value) <= 128

  defp external_reference?(provider) do
    Enum.any?([provider.request_id, provider.operation_id, provider.session_id], &is_binary/1)
  end
end
