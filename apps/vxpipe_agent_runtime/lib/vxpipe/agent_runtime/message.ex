defmodule Vxpipe.AgentRuntime.Message do
  @moduledoc "A normalized conversation message retained by an agent session."

  alias Vxpipe.AgentRuntime.ToolCall

  @derive {Inspect, only: [:role, :name, :tool_call_id]}
  @enforce_keys [:role, :content]
  defstruct @enforce_keys ++ [origin: nil, name: nil, tool_call_id: nil, tool_calls: []]

  @type role :: :system | :user | :assistant | :tool
  @type origin :: :caller | :engine | nil
  @type t :: %__MODULE__{
          role: role(),
          content: String.t(),
          origin: origin(),
          name: String.t() | nil,
          tool_call_id: String.t() | nil,
          tool_calls: [ToolCall.t()]
        }

  @spec system(String.t()) :: t()
  def system(content) when is_binary(content), do: %__MODULE__{role: :system, content: content}

  @spec user(String.t(), :caller | :engine) :: t()
  def user(content, origin \\ :caller)

  def user(content, origin) when is_binary(content) and origin in [:caller, :engine] do
    %__MODULE__{role: :user, content: content, origin: origin}
  end

  @spec assistant(String.t(), [ToolCall.t()]) :: t()
  def assistant(content, tool_calls) when is_binary(content) and is_list(tool_calls) do
    %__MODULE__{role: :assistant, content: content, tool_calls: tool_calls}
  end

  @spec tool(ToolCall.t(), map()) :: t()
  def tool(%ToolCall{} = call, result) when is_map(result) do
    %__MODULE__{
      role: :tool,
      content: JSON.encode!(result),
      name: call.name,
      tool_call_id: call.id
    }
  end
end
