defmodule Vxpipe.CallEngine.AgentRuntime.ModelContextSource do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.ModelContextSource

  alias Vxpipe.CallEngine.CallVariables.Binding

  @derive {Inspect, only: []}
  @enforce_keys [:variable_binding, :transfer_reason]
  defstruct @enforce_keys ++ [coordinator: nil]

  @type t :: %__MODULE__{
          variable_binding: nil | Binding.t(),
          transfer_reason: nil | String.t(),
          coordinator: GenServer.server() | nil
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

  @doc "Attaches the coordinator for bounded provisional in-flight audio."
  @spec with_coordinator(t(), GenServer.server()) :: t()
  def with_coordinator(%__MODULE__{} = source, coordinator)
      when not is_nil(coordinator) do
    %{source | coordinator: coordinator}
  end

  @impl true
  def snapshot(%__MODULE__{} = source, correlation, timeout_ms)
      when is_integer(timeout_ms) and timeout_ms > 0 do
    with {:ok, variables} <- variable_projection(source.variable_binding, timeout_ms) do
      context =
        %{}
        |> put_optional("call_variables", variables)
        |> put_optional("transfer", transfer_context(source.transfer_reason))
        |> put_optional("in_flight_audio", in_flight_audio(source, correlation, timeout_ms))

      {:ok, context}
    else
      _unavailable -> {:error, :model_context_unavailable}
    end
  end

  defp in_flight_audio(%{coordinator: nil}, _correlation, _timeout), do: nil

  defp in_flight_audio(%{coordinator: coordinator}, correlation, timeout) do
    Vxpipe.CallEngine.AgentRuntime.Coordinator.in_flight_audio(coordinator, correlation, timeout)
  end

  defp variable_projection(nil, _timeout_ms), do: {:ok, nil}

  defp variable_projection(%Binding{} = binding, timeout_ms),
    do: Binding.projection(binding, timeout_ms)

  defp transfer_context(nil), do: nil
  defp transfer_context(reason), do: %{"reason" => reason}

  defp put_optional(context, _key, nil), do: context
  defp put_optional(context, key, value), do: Map.put(context, key, value)
end
