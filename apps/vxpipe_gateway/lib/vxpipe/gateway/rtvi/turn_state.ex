defmodule Vxpipe.Gateway.RTVI.TurnState do
  @moduledoc false

  alias Vxpipe.CallEngine.Event.{AgentSpeechStarted, AgentTurnCompleted, TextOutput}

  defstruct spoken_outputs: %{}

  @type action ::
          {:event, TextOutput.t() | AgentSpeechStarted.t() | AgentTurnCompleted.t()}
          | {:spoken_progress, TextOutput.t(), String.t(), :in_progress | :completed}
          | {:user_mute, :started | :stopped, String.t()}

  @type t :: %__MODULE__{spoken_outputs: %{String.t() => TextOutput.t()}}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec input_enabled?(t()) :: boolean()
  def input_enabled?(%__MODULE__{spoken_outputs: spoken_outputs}) do
    map_size(spoken_outputs) == 0
  end

  @spec project(t(), TextOutput.t() | AgentSpeechStarted.t() | AgentTurnCompleted.t()) ::
          {t(), [action()]}
  def project(%__MODULE__{} = state, %TextOutput{will_be_spoken: false} = event) do
    {state, [{:event, event}]}
  end

  def project(%__MODULE__{} = state, %TextOutput{will_be_spoken: true} = event) do
    input_was_enabled? = input_enabled?(state)

    state = %{
      state
      | spoken_outputs: Map.put(state.spoken_outputs, event.correlation_id, event)
    }

    actions =
      if input_was_enabled? do
        [{:event, event}, {:user_mute, :started, event.id}]
      else
        [{:event, event}]
      end

    {state, actions}
  end

  def project(%__MODULE__{} = state, %AgentSpeechStarted{} = event) do
    case Map.fetch(state.spoken_outputs, event.correlation_id) do
      {:ok, output} ->
        {state,
         [
           {:event, event},
           {:spoken_progress, output, event.id, :in_progress}
         ]}

      :error ->
        {state, [{:event, event}]}
    end
  end

  def project(%__MODULE__{} = state, %AgentTurnCompleted{} = event) do
    case Map.pop(state.spoken_outputs, event.correlation_id) do
      {nil, _spoken_outputs} ->
        {state, [{:event, event}]}

      {output, spoken_outputs} ->
        state = %{state | spoken_outputs: spoken_outputs}

        actions = [
          {:spoken_progress, output, event.id, :completed},
          {:event, event}
        ]

        actions =
          if input_enabled?(state) do
            actions ++ [{:user_mute, :stopped, event.id}]
          else
            actions
          end

        {state, actions}
    end
  end
end
