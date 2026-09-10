defmodule Vxpipe.AgentRuntime.Request do
  @moduledoc "A single input admitted to an agent-runtime session."

  @derive {Inspect, only: [:correlation]}
  @enforce_keys [:input, :correlation]
  defstruct @enforce_keys ++ [pending_invocations: []]

  @type t :: %__MODULE__{
          input: String.t(),
          correlation: map(),
          pending_invocations: [Vxpipe.AgentRuntime.PendingInvocation.t()]
        }
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

  @spec with_pending_invocations(t(), [Vxpipe.AgentRuntime.PendingInvocation.t()]) :: t()
  def with_pending_invocations(%__MODULE__{} = request, pending_invocations)
      when is_list(pending_invocations) do
    %{request | pending_invocations: pending_invocations}
  end
end
