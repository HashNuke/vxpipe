defmodule Vxpipe.Providers.Cartesia.STTTurns do
  @moduledoc false
  @derive {Inspect, only: [:eager?]}
  defstruct [:request_id, :turn, text: "", eager?: false]

  def new, do: %__MODULE__{}
  def finished?(%__MODULE__{request_id: id, turn: nil}), do: is_binary(id)
  def finished?(%__MODULE__{}), do: false

  def advance(%__MODULE__{request_id: nil} = state, {:ready, id, nil}) do
    {:ok, %{state | request_id: id},
     {:ready, [readiness: :provider_acknowledged, provider_request_id: id]}}
  end

  def advance(%__MODULE__{request_id: id, turn: nil} = state, {:speech_started, id, nil})
      when is_binary(id) do
    state = %{state | turn: make_ref(), text: "", eager?: false}
    {:ok, state, {:speech_started, identity(state)}}
  end

  def advance(
        %__MODULE__{request_id: id, turn: turn, eager?: true} = state,
        {:turn_resumed, id, nil}
      )
      when is_reference(turn),
      do: {:ok, %{state | eager?: false}, {:turn_resumed, identity(state)}}

  def advance(%__MODULE__{request_id: id, turn: turn} = state, {kind, id, text})
      when is_reference(turn) and kind in [:transcript, :eager_turn_ended, :turn_ended] do
    if String.starts_with?(text, state.text) and (not state.eager? or kind == :turn_ended) do
      fields = identity(state) ++ [text: text]

      fields =
        if kind == :transcript, do: fields, else: fields ++ [endpointing: :provider_semantic]

      next =
        case kind do
          :turn_ended -> %{state | turn: nil, text: "", eager?: false}
          :eager_turn_ended -> %{state | text: text, eager?: true}
          :transcript -> %{state | text: text}
        end

      {:ok, next, {kind, fields}}
    else
      {:error, :invalid_transition}
    end
  end

  def advance(_state, _event), do: {:error, :invalid_transition}

  defp identity(state), do: [turn_ref: state.turn, provider_request_id: state.request_id]
end
