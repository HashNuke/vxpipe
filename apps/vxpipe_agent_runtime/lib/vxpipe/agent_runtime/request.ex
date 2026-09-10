defmodule Vxpipe.AgentRuntime.Request do
  @moduledoc "A single input admitted to an agent-runtime session."

  @derive {Inspect, only: [:origin, :correlation]}
  @enforce_keys [:input, :origin, :correlation]
  defstruct @enforce_keys

  @type origin :: :caller | :engine
  @type t :: %__MODULE__{input: String.t(), origin: origin(), correlation: map()}
  @default_max_input_bytes 64 * 1_024

  @spec new(String.t(), map(), keyword()) :: {:ok, t()} | {:error, atom()}
  def new(input, correlation, options \\ [])

  def new(input, correlation, options)
      when is_binary(input) and is_map(correlation) and is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             max_input_bytes: @default_max_input_bytes,
             origin: :caller
           ) do
      max_input_bytes = Keyword.fetch!(options, :max_input_bytes)
      origin = Keyword.fetch!(options, :origin)

      cond do
        input == "" -> {:error, :invalid_input}
        origin not in [:caller, :engine] -> {:error, :invalid_origin}
        not (is_integer(max_input_bytes) and max_input_bytes > 0) -> {:error, :invalid_limit}
        byte_size(input) > max_input_bytes -> {:error, :input_too_large}
        true -> {:ok, %__MODULE__{input: input, origin: origin, correlation: correlation}}
      end
    else
      _invalid -> {:error, :invalid_request}
    end
  end

  def new(_input, _correlation, _options), do: {:error, :invalid_request}
end
