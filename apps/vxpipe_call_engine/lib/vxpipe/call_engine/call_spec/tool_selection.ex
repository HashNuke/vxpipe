defmodule Vxpipe.CallEngine.CallSpec.ToolSelection do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpecValidation

  @enforce_keys [:name, :type, :tool, :conversation_mode]
  defstruct @enforce_keys ++ [:integration]

  @type t :: %__MODULE__{
          name: String.t(),
          type: :host | :mcp | :platform,
          tool: String.t(),
          conversation_mode: :blocking | :non_blocking,
          integration: nil | String.t()
        }

  def new(name, value, path) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with {:ok, name} <- CallSpecValidation.identifier(name, code, message, path),
         :ok <- reject_reserved(name, code, message, path),
         {:ok, input} <-
           CallSpecValidation.normalize_map(
             value,
             [:type, :tool, :integration, :conversation_mode],
             code,
             message,
             path
           ),
         {:ok, type_input} <- CallSpecValidation.fetch(input, :type, code, message, path),
         {:ok, type} <-
           CallSpecValidation.enum(
             type_input,
             [host: "host", mcp: "mcp", platform: "platform"],
             code,
             message,
             path ++ ["type"]
           ),
         {:ok, tool_input} <- CallSpecValidation.fetch(input, :tool, code, message, path),
         {:ok, tool} <-
           CallSpecValidation.identifier(tool_input, code, message, path ++ ["tool"]),
         {:ok, conversation_mode} <- conversation_mode(input, code, message, path),
         {:ok, integration} <- integration(type, input, code, message, path) do
      {:ok,
       %__MODULE__{
         name: name,
         type: type,
         tool: tool,
         conversation_mode: conversation_mode,
         integration: integration
       }}
    end
  end

  defp conversation_mode(input, code, message, path) do
    CallSpecValidation.enum(
      Map.get(input, :conversation_mode, "blocking"),
      [blocking: "blocking", non_blocking: "non_blocking"],
      code,
      message,
      path ++ ["conversation_mode"]
    )
  end

  defp integration(:mcp, input, code, message, path) do
    with {:ok, value} <- CallSpecValidation.fetch(input, :integration, code, message, path) do
      CallSpecValidation.identifier(value, code, message, path ++ ["integration"])
    end
  end

  defp integration(type, input, code, message, path) when type in [:host, :platform] do
    if Map.has_key?(input, :integration) do
      CallSpecValidation.invalid(
        code,
        message,
        path ++ ["integration"],
        "is only supported for MCP tools"
      )
    else
      {:ok, nil}
    end
  end

  defp reject_reserved(name, code, message, path)
       when name in ["transfer", "read_variables", "update_variables", "update_variable"] do
    CallSpecValidation.invalid(code, message, path, "collides with a platform tool name")
  end

  defp reject_reserved(_name, _code, _message, _path), do: :ok
end
