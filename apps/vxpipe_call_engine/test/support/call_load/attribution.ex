defmodule Vxpipe.CallEngine.CallLoad.Attribution do
  @moduledoc "Immutable input origins with separately bound caller, public and sink IDs."

  def new, do: %{current: nil, inputs: %{}, bindings: %{caller: %{}, public: %{}, sink: %{}}}

  def begin_input(state, index, started) do
    if state.current != nil and not ready?(state),
      do: raise(ArgumentError, "unsettled attribution before next input")

    if index not in 1..4 or Map.has_key?(state.inputs, index),
      do: raise(ArgumentError, "invalid input generation")

    input = %{started: started, finished: false, observed: MapSet.new()}
    %{state | current: index, inputs: Map.put(state.inputs, index, input)}
  end

  def observe(state, kind, id, at) when kind in [:caller, :public, :sink] and is_binary(id) do
    input = Map.fetch!(state.inputs, state.current)
    bindings = Map.fetch!(state.bindings, kind)
    if Map.has_key?(bindings, id), do: raise(ArgumentError, "duplicate correlation #{kind}")

    if MapSet.member?(input.observed, kind),
      do: raise(ArgumentError, "uncorrelated extra #{kind} onset")

    state = put_in(state.bindings[kind][id], %{input: state.current, started: input.started})
    state = put_in(state.inputs[state.current].observed, MapSet.put(input.observed, kind))
    {state, at - input.started}
  end

  def finish_input(state, index) do
    if index != state.current, do: raise(ArgumentError, "uncorrelated input completion")
    put_in(state.inputs[index].finished, true)
  end

  def ready?(%{current: nil}), do: false

  def ready?(state) do
    input = Map.fetch!(state.inputs, state.current)
    input.finished and MapSet.size(input.observed) == 3
  end

  def elapsed(state, kind, id, at), do: at - binding!(state, kind, id).started
  def input(state, kind, id), do: binding!(state, kind, id).input

  defp binding!(state, kind, id) do
    case Map.fetch(Map.fetch!(state.bindings, kind), id) do
      {:ok, binding} -> binding
      :error -> raise ArgumentError, "unknown correlation #{kind}"
    end
  end
end
