defmodule Vxpipe.AgentRuntime.CompactionObservation do
  @moduledoc "Bounded provider usage observed for one context-compaction attempt."

  alias Vxpipe.AgentRuntime.CompactionResult

  @maximum_usage_bytes 16 * 1_024
  @maximum_provider_metadata_bytes 64 * 1_024

  @derive {Inspect, only: [:outcome]}
  @enforce_keys [:usage, :provider_metadata, :outcome]
  defstruct @enforce_keys

  @type outcome :: :succeeded | :failed
  @type t :: %__MODULE__{
          usage: map(),
          provider_metadata: map(),
          outcome: outcome()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_compaction_observation}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <-
           Keyword.validate(attributes, [:usage, :provider_metadata, :outcome]),
         usage when is_map(usage) <- Keyword.get(attributes, :usage),
         true <- :erlang.external_size(usage) <= @maximum_usage_bytes,
         provider_metadata when is_map(provider_metadata) <-
           Keyword.get(attributes, :provider_metadata),
         true <-
           :erlang.external_size(provider_metadata) <= @maximum_provider_metadata_bytes,
         outcome when outcome in [:succeeded, :failed] <- Keyword.get(attributes, :outcome) do
      {:ok,
       %__MODULE__{
         usage: usage,
         provider_metadata: provider_metadata,
         outcome: outcome
       }}
    else
      _invalid -> {:error, :invalid_compaction_observation}
    end
  end

  def new(_attributes), do: {:error, :invalid_compaction_observation}

  @spec unmeasured_failure() :: t()
  def unmeasured_failure do
    %__MODULE__{usage: %{}, provider_metadata: %{}, outcome: :failed}
  end

  @spec from_result(CompactionResult.t(), outcome()) :: t()
  def from_result(%CompactionResult{} = result, outcome)
      when outcome in [:succeeded, :failed] do
    %__MODULE__{
      usage: result.usage,
      provider_metadata: result.provider_metadata,
      outcome: outcome
    }
  end
end
