defmodule Vxpipe.CallEngine.Tool.InvocationSubmission do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{Context, InvocationBinding}

  @derive {Inspect, only: [:invocation_id, :tool_name, :conversation_mode]}
  @enforce_keys [
    :invocation_id,
    :tool_name,
    :conversation_mode,
    :binding,
    :arguments,
    :context,
    :fingerprint
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @maximum_invocation_id_bytes 256

  @spec new(InvocationBinding.t(), map(), Context.t(), String.t()) ::
          {:ok, t()} | {:error, :invalid_submission}
  def new(%InvocationBinding{} = binding, arguments, %Context{} = context, invocation_id)
      when is_map(arguments) and is_binary(invocation_id) and invocation_id != "" and
             byte_size(invocation_id) <= @maximum_invocation_id_bytes do
    if InvocationBinding.valid?(binding) and compatible_tool_call?(context, invocation_id) do
      context = %{context | tool_call_id: invocation_id}

      {:ok,
       %__MODULE__{
         invocation_id: invocation_id,
         tool_name: binding.name,
         conversation_mode: binding.conversation_mode,
         binding: binding,
         arguments: arguments,
         context: context,
         fingerprint: fingerprint(binding, arguments, context)
       }}
    else
      {:error, :invalid_submission}
    end
  end

  def new(_binding, _arguments, _context, _invocation_id), do: {:error, :invalid_submission}

  defp compatible_tool_call?(%Context{tool_call_id: nil}, _invocation_id), do: true

  defp compatible_tool_call?(%Context{tool_call_id: invocation_id}, invocation_id), do: true

  defp compatible_tool_call?(_context, _invocation_id), do: false

  defp fingerprint(binding, arguments, context) do
    :crypto.hash(
      :sha256,
      :erlang.term_to_binary({binding, arguments, context}, [:deterministic])
    )
  end
end
