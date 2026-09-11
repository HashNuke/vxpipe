defmodule Vxpipe.CallEngine.AgentRuntime.ModelContextSource do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.ModelContextSource

  alias Vxpipe.CallEngine.CallVariables.Binding

  @derive {Inspect, only: []}
  @enforce_keys [:variable_binding, :transfer_reason]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          variable_binding: nil | Binding.t(),
          transfer_reason: nil | String.t()
        }

  @spec new(nil | Binding.t(), nil | String.t()) :: nil | t()
  def new(nil, nil), do: nil

  def new(variable_binding, transfer_reason)
      when (is_nil(variable_binding) or is_struct(variable_binding, Binding)) and
             (is_nil(transfer_reason) or is_binary(transfer_reason)) do
    %__MODULE__{
      variable_binding: variable_binding,
      transfer_reason: transfer_reason
    }
  end

  @impl true
  def snapshot(%__MODULE__{} = source, _correlation, timeout_ms)
      when is_integer(timeout_ms) and timeout_ms > 0 do
    with {:ok, variables} <- variable_projection(source.variable_binding, timeout_ms) do
      context =
        %{}
        |> put_optional("call_variables", variables)
        |> put_optional("transfer", transfer_context(source.transfer_reason))

      {:ok, context}
    else
      _unavailable -> {:error, :model_context_unavailable}
    end
  end

  defp variable_projection(nil, _timeout_ms), do: {:ok, nil}

  defp variable_projection(%Binding{} = binding, timeout_ms),
    do: Binding.projection(binding, timeout_ms)

  defp transfer_context(nil), do: nil
  defp transfer_context(reason), do: %{"reason" => reason}

  defp put_optional(context, _key, nil), do: context
  defp put_optional(context, key, value), do: Map.put(context, key, value)
end
