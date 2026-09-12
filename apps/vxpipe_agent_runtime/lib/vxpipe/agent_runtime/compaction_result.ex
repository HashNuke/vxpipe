defmodule Vxpipe.AgentRuntime.CompactionResult do
  @moduledoc "A bounded summary and its observed model metadata."

  @maximum_summary_bytes 256 * 1_024
  @maximum_usage_bytes 16 * 1_024
  @maximum_provider_metadata_bytes 64 * 1_024

  @derive {Inspect, only: []}
  @enforce_keys [:summary, :usage, :provider_metadata]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          summary: String.t(),
          usage: map(),
          provider_metadata: map()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_compaction_result}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <-
           Keyword.validate(attributes, [:summary, usage: %{}, provider_metadata: %{}]),
         summary when is_binary(summary) <- Keyword.get(attributes, :summary),
         true <- String.valid?(summary) and String.trim(summary) != "",
         true <- byte_size(summary) <= @maximum_summary_bytes,
         usage when is_map(usage) <- Keyword.fetch!(attributes, :usage),
         true <- :erlang.external_size(usage) <= @maximum_usage_bytes,
         provider_metadata when is_map(provider_metadata) <-
           Keyword.fetch!(attributes, :provider_metadata),
         true <-
           :erlang.external_size(provider_metadata) <= @maximum_provider_metadata_bytes do
      {:ok,
       %__MODULE__{
         summary: summary,
         usage: usage,
         provider_metadata: provider_metadata
       }}
    else
      _invalid -> {:error, :invalid_compaction_result}
    end
  end

  def new(_attributes), do: {:error, :invalid_compaction_result}
end
