defmodule Vxpipe.AgentRuntime.Result do
  @moduledoc "The bounded terminal result of one admitted runtime request."

  @derive {Inspect, only: [:status, :correlation, :reason]}
  @enforce_keys [:status, :correlation]
  defstruct @enforce_keys ++ [:output, :reason]

  @type status :: :completed | :failed | :cancelled
  @type t :: %__MODULE__{
          status: status(),
          correlation: map(),
          output: String.t() | nil,
          reason: atom() | nil
        }

  @spec completed(String.t(), map()) :: t()
  def completed(output, correlation) when is_binary(output) and is_map(correlation) do
    %__MODULE__{status: :completed, output: output, correlation: correlation}
  end

  @spec failed(atom(), map()) :: t()
  def failed(reason, correlation) when is_atom(reason) and is_map(correlation) do
    %__MODULE__{status: :failed, reason: reason, correlation: correlation}
  end

  @spec cancelled(map()) :: t()
  def cancelled(correlation) when is_map(correlation) do
    %__MODULE__{status: :cancelled, correlation: correlation}
  end
end
