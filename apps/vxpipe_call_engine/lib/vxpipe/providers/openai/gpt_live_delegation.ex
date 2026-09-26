defmodule Vxpipe.Providers.OpenAI.GPTLiveDelegation do
  @moduledoc "Tracks Responses delegations and their outstanding host function calls."

  defstruct delegations: %{}, calls: %{}

  def new, do: %__MODULE__{}

  def created(%__MODULE__{} = state, id, "responses", response_id) do
    delegation = %{
      response_id: response_id,
      calls: MapSet.new(),
      seen: MapSet.new(),
      completed?: false,
      discarded?: false,
      continued?: false
    }

    {:ok, %{state | delegations: Map.put(state.delegations, id, delegation)}}
  end

  def created(%__MODULE__{}, _id, _target, _response_id), do: {:error, :unsupported_delegation}

  def event(%__MODULE__{} = state, id, %{
        "type" => "response.output_item.done",
        "item" => %{
          "type" => "function_call",
          "call_id" => call_id,
          "name" => name,
          "arguments" => encoded
        }
      }) do
    with {:ok, delegation} <- Map.fetch(state.delegations, id),
         true <- valid_name?(call_id) and valid_name?(name),
         true <- is_binary(encoded) and byte_size(encoded) <= 65_536,
         {:ok, arguments} <- JSON.decode(encoded),
         true <- is_map(arguments),
         true <- Vxpipe.CallEngine.Speech.ToolArguments.valid?(arguments) do
      if delegation.discarded? or MapSet.member?(delegation.seen, call_id) do
        {:ok, state, []}
      else
        call_ref = make_ref()

        delegation = %{
          delegation
          | calls: MapSet.put(delegation.calls, call_id),
            seen: MapSet.put(delegation.seen, call_id)
        }

        state = %{
          state
          | delegations: Map.put(state.delegations, id, delegation),
            calls: Map.put(state.calls, call_ref, %{delegation_id: id, call_id: call_id})
        }

        {:ok, state, [{:tool_call, call_ref, name, arguments}]}
      end
    else
      _invalid -> {:error, :invalid_message}
    end
  end

  def event(%__MODULE__{} = state, id, %{"type" => "response.completed"}) do
    update_delegation(state, id, fn delegation -> %{delegation | completed?: true} end)
  end

  def event(%__MODULE__{} = state, id, %{"type" => type})
      when type in ["response.failed", "response.incomplete"] do
    with {:ok, delegation} <- Map.fetch(state.delegations, id) do
      calls =
        Map.reject(state.calls, fn {_ref, call} -> call.delegation_id == id end)

      delegation = %{delegation | calls: MapSet.new(), discarded?: true}

      {:ok, %{state | delegations: Map.put(state.delegations, id, delegation), calls: calls}, []}
    else
      :error -> {:error, :invalid_message}
    end
  end

  def event(%__MODULE__{} = state, id, %{
        "type" => "response.created",
        "response" => %{"id" => response_id}
      }) do
    update_delegation(state, id, fn delegation -> %{delegation | response_id: response_id} end)
  end

  def event(%__MODULE__{} = state, id, %{"type" => _type}) do
    if Map.has_key?(state.delegations, id),
      do: {:ok, state, []},
      else: {:error, :invalid_message}
  end

  def event(%__MODULE__{}, _id, _event), do: {:error, :invalid_message}

  def result(%__MODULE__{} = state, call_ref) do
    with {:ok, %{delegation_id: id, call_id: call_id}} <- Map.fetch(state.calls, call_ref),
         {:ok, delegation} <- Map.fetch(state.delegations, id),
         false <- delegation.discarded? do
      delegation = %{delegation | calls: MapSet.delete(delegation.calls, call_id)}

      state = %{
        state
        | calls: Map.delete(state.calls, call_ref),
          delegations: Map.put(state.delegations, id, delegation)
      }

      {state, continuation} = maybe_continue(state, id)
      {:ok, state, call_id, continuation}
    else
      _invalid -> {:error, :stale_request}
    end
  end

  defp update_delegation(state, id, update) do
    with {:ok, delegation} <- Map.fetch(state.delegations, id) do
      state = %{state | delegations: Map.put(state.delegations, id, update.(delegation))}
      {state, continuation} = maybe_continue(state, id)
      {:ok, state, continuation}
    else
      :error -> {:error, :invalid_message}
    end
  end

  defp maybe_continue(state, id) do
    delegation = Map.fetch!(state.delegations, id)

    if delegation.completed? and not delegation.discarded? and
         not delegation.continued? and MapSet.size(delegation.seen) > 0 and
         MapSet.size(delegation.calls) == 0 do
      delegation = %{delegation | continued?: true}
      {%{state | delegations: Map.put(state.delegations, id, delegation)}, [:continue]}
    else
      {state, []}
    end
  end

  defp valid_name?(value) when is_binary(value) and byte_size(value) in 1..256,
    do: Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, value)

  defp valid_name?(_value), do: false
end
