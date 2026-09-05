defmodule Vxpipe.Gateway.RTVI.TurnState do
  @moduledoc false

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechProgressed,
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnInterrupted,
    TextOutput
  }

  defstruct active_spoken_output: nil, pending_spoken_outputs: :queue.new()

  @type action ::
          {:event,
           TextOutput.t()
           | AgentSpeechStarted.t()
           | AgentTurnCompleted.t()
           | AgentTurnInterrupted.t()}
          | {:interruption_context, AgentTurnInterrupted.t()}
          | {:spoken_progress, TextOutput.t(), String.t(), progress()}

  @type progress :: :in_progress | :completed

  @type t :: %__MODULE__{
          active_spoken_output: TextOutput.t() | nil,
          pending_spoken_outputs: :queue.queue(TextOutput.t())
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec project(
          t(),
          TextOutput.t()
          | AgentSpeechStarted.t()
          | AgentSpeechProgressed.t()
          | AgentTurnCompleted.t()
          | AgentTurnInterrupted.t()
        ) ::
          {t(), [action()]}
  def project(%__MODULE__{} = state, %TextOutput{will_be_spoken: false} = event) do
    {state, [{:event, event}]}
  end

  def project(%__MODULE__{} = state, %TextOutput{will_be_spoken: true} = event) do
    case state.active_spoken_output do
      nil ->
        state = %{state | active_spoken_output: event}
        {state, [{:event, event}]}

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

  def project(%__MODULE__{} = state, %AgentSpeechProgressed{}), do: {state, []}

  def project(%__MODULE__{} = state, %AgentTurnCompleted{} = event) do
    case state.active_spoken_output do
      %TextOutput{correlation_id: correlation_id} = output
      when correlation_id == event.correlation_id ->
        complete_active_output(state, output, event)

      _other ->
        {state, [{:event, event}]}
    end
  end

  def project(%__MODULE__{} = state, %AgentTurnInterrupted{} = event) do
    cond do
      active_turn?(state, event.correlation_id) ->
        state = %{state | active_spoken_output: nil, pending_spoken_outputs: :queue.new()}

        {state,
         [
           {:event, event},
           {:interruption_context, event}
         ]}

      pending_turn?(state, event.correlation_id) ->
        {remove_pending_turn(state, event.correlation_id), []}

      true ->
        {state, [{:event, event}, {:interruption_context, event}]}
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
        {state, actions}
    end
  end

  defp active_turn?(state, correlation_id) do
    match?(%TextOutput{correlation_id: ^correlation_id}, state.active_spoken_output)
  end

  defp pending_turn?(state, correlation_id) do
    Enum.any?(:queue.to_list(state.pending_spoken_outputs), fn output ->
      output.correlation_id == correlation_id
    end)
  end

  defp remove_pending_turn(state, correlation_id) do
    pending =
      state.pending_spoken_outputs
      |> :queue.to_list()
      |> Enum.reject(&(&1.correlation_id == correlation_id))
      |> :queue.from_list()

    %{state | pending_spoken_outputs: pending}
  end
end
