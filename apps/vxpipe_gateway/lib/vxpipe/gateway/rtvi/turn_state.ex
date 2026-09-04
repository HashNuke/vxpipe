defmodule Vxpipe.Gateway.RTVI.TurnState do
  @moduledoc false

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechProgressed,
    AgentSpeechStarted,
    AgentTurnCompleted,
    TextOutput
  }

  defstruct active_spoken_output: nil, pending_spoken_outputs: :queue.new()

  @type action ::
          {:event, TextOutput.t() | AgentSpeechStarted.t() | AgentTurnCompleted.t()}
          | {:spoken_progress, TextOutput.t(), String.t(), progress()}
          | {:user_mute, :started | :stopped, String.t()}

  @type progress ::
          :in_progress | :completed | {:in_progress, pos_integer(), pos_integer()}

  @type t :: %__MODULE__{
          active_spoken_output: TextOutput.t() | nil,
          pending_spoken_outputs: :queue.queue(TextOutput.t())
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec input_enabled?(t()) :: boolean()
  def input_enabled?(%__MODULE__{active_spoken_output: output}), do: output == nil

  @spec project(
          t(),
          TextOutput.t()
          | AgentSpeechStarted.t()
          | AgentSpeechProgressed.t()
          | AgentTurnCompleted.t()
        ) ::
          {t(), [action()]}
  def project(%__MODULE__{} = state, %TextOutput{will_be_spoken: false} = event) do
    {state, [{:event, event}]}
  end

  def project(%__MODULE__{} = state, %TextOutput{will_be_spoken: true} = event) do
    case state.active_spoken_output do
      nil ->
        state = %{state | active_spoken_output: event}
        {state, [{:event, event}, {:user_mute, :started, event.id}]}

      %TextOutput{} ->
        pending = :queue.in(event, state.pending_spoken_outputs)
        {%{state | pending_spoken_outputs: pending}, []}
    end
  end

  def project(%__MODULE__{} = state, %AgentSpeechStarted{} = event) do
    case state.active_spoken_output do
      %TextOutput{correlation_id: correlation_id} = output
      when correlation_id == event.correlation_id ->
        {state,
         [
           {:event, event},
           {:spoken_progress, output, event.id, :in_progress}
         ]}

      _other ->
        {state, [{:event, event}]}
    end
  end

  def project(%__MODULE__{} = state, %AgentSpeechProgressed{} = event) do
    case state.active_spoken_output do
      %TextOutput{correlation_id: correlation_id} = output
      when correlation_id == event.correlation_id ->
        {state,
         [
           {:spoken_progress, output, event.id, {:in_progress, event.played_ms, event.total_ms}}
         ]}

      _other ->
        {state, []}
    end
  end

  def project(%__MODULE__{} = state, %AgentTurnCompleted{} = event) do
    case state.active_spoken_output do
      %TextOutput{correlation_id: correlation_id} = output
      when correlation_id == event.correlation_id ->
        complete_active_output(state, output, event)

      _other ->
        {state, [{:event, event}]}
    end
  end

  defp complete_active_output(state, output, event) do
    actions = [
      {:spoken_progress, output, event.id, :completed},
      {:event, event}
    ]

    case :queue.out(state.pending_spoken_outputs) do
      {{:value, next_output}, pending} ->
        state = %{
          state
          | active_spoken_output: next_output,
            pending_spoken_outputs: pending
        }

        {state, actions ++ [{:event, next_output}]}

      {:empty, pending} ->
        state = %{state | active_spoken_output: nil, pending_spoken_outputs: pending}
        {state, actions ++ [{:user_mute, :stopped, event.id}]}
    end
  end
end
