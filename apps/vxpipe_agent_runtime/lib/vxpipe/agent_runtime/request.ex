defmodule Vxpipe.AgentRuntime.Request do
  @moduledoc "A single input admitted to an agent-runtime session."

  @derive {Inspect, only: [:correlation]}
  @enforce_keys [:input, :correlation]
  defstruct @enforce_keys

  @type t :: %__MODULE__{input: String.t(), correlation: map()}
  @default_max_input_bytes 64 * 1_024

  @spec new(String.t(), map(), keyword()) :: {:ok, t()} | {:error, atom()}
  def new(input, correlation, options \\ [])

  def new(input, correlation, options)
      when is_binary(input) and is_map(correlation) and is_list(options) do
    max_input_bytes = Keyword.get(options, :max_input_bytes, @default_max_input_bytes)

    cond do
      input == "" -> {:error, :invalid_input}
      not (is_integer(max_input_bytes) and max_input_bytes > 0) -> {:error, :invalid_limit}
      byte_size(input) > max_input_bytes -> {:error, :input_too_large}
      true -> {:ok, %__MODULE__{input: input, correlation: correlation}}
    end
  end

  def new(_input, _correlation, _options), do: {:error, :invalid_request}
end
