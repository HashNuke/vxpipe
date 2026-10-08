defmodule Vxpipe.Providers.Google.STSCommands do
  @moduledoc "Ordered native Google input and engine-owned opening commands."

  alias Vxpipe.CallEngine.Speech.Event
  alias Vxpipe.Providers.Google.{STS, STSInput, STSOpening, STSResumption}

  def execute(command, %{response_start?: true, resuming?: true} = state)
      when is_tuple(command) and
             elem(command, 0) in [:push_audio, :push_text, :begin_opening, :input_activity],
      do: {:reply, {:error, :busy}, state}

  def execute({:push_audio, audio}, %{ready?: true} = state) do
    with {:ok, _encoded} <- STS.encode_audio(audio),
         :ok <- state.wire_module.send_audio(state.wire, audio) do
      {:reply, :ok, STSResumption.accept_audio(state, audio)}
    else
      {:error, :invalid_audio} -> {:reply, {:error, :session_failed}, state}
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def execute({:push_audio, _audio}, state),
    do: {:reply, {:error, :session_failed}, state}

  def execute({:begin_opening, reference, opening}, %{ready?: true} = state) do
    turn = make_ref()

    with true <- STSResumption.input_quiescent?(state),
         {:ok, cue, fixed} <- STSOpening.prepare(opening),
         :ok <- state.wire_module.send_text(state.wire, cue),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :provider_reported
           ),
         :ok <- opening_started(state, reference, turn) do
      next =
        %{
          STSResumption.begin_turn(state)
          | input_turn: turn,
            input_text: nil,
            input_ended?: true,
            fixed_opening: fixed
        }

      {:reply, :ok, STSResumption.await_model_activity(next)}
    else
      false -> {:reply, {:error, :busy}, state}
      {:error, :invalid_opening} -> {:reply, {:error, :invalid_opening}, state}
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def execute({:begin_opening, _reference, _opening}, state),
    do: {:reply, {:error, :session_failed}, state}

  def execute({:push_text, reference, text}, %{ready?: true} = state) do
    turn = make_ref()

    with {:ok, _encoded} <- STS.encode_text(text),
         :ok <- state.wire_module.send_text(state.wire, text),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :provider_reported
           ),
         {:ok, state} <-
           STSInput.open_text_turn(%{
             STSResumption.begin_turn(state)
             | input_turn: turn,
               input_text: text
           }) do
      {:reply, :ok, STSResumption.await_model_activity(state)}
    else
      {:error, :invalid_text} -> {:reply, {:error, :invalid_text}, state}
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def execute({:push_text, _reference, _text}, state),
    do: {:reply, {:error, :session_failed}, state}

  def execute(
        {:input_activity, _boundary},
        %{config: %{turn_control: "provider"}} = state
      ),
      do: {:reply, {:error, :unsupported_operation}, state}

  def execute(
        {:input_activity, :started},
        %{ready?: true, caller: %{ended?: false}} = state
      ),
      do: {:reply, :ok, state}

  def execute({:input_activity, :ended}, %{ready?: true, caller: nil} = state),
    do: {:reply, :ok, state}

  def execute(
        {:input_activity, :ended},
        %{ready?: true, caller: %{ended?: true}} = state
      ),
      do: {:reply, :ok, state}

  def execute({:input_activity, boundary}, %{ready?: true} = state)
      when boundary in [:started, :ended] do
    with :ok <- state.wire_module.send_activity(state.wire, boundary),
         {:ok, state} <- STSInput.activity_boundary(boundary, state) do
      {:reply, :ok, STSResumption.await_model_activity(state)}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def execute({:input_activity, _boundary}, state),
    do: {:reply, {:error, :session_failed}, state}

  defp opening_started(%{response_start?: true}, _reference, _turn), do: :ok

  defp opening_started(state, reference, turn),
    do: Event.emit(state.channel, :opening_started, request_ref: reference, turn_ref: turn)
end
