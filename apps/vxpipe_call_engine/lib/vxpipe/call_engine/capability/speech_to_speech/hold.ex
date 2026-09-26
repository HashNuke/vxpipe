defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.Hold do
  @moduledoc "Hold and release behavior for an STS capability allocation."

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.{Input, Output, ToolEvents}
  alias Vxpipe.CallEngine.Speech.Session

  def hold(%{descriptor: %{hold: :mute}} = state) do
    case Session.set_input_hold(state.session, true) do
      :ok ->
        state = state |> Input.hold() |> Map.put(:input_turns, MapSet.new())

        case Output.retire_stale_pending(state) do
          {:ok, state} ->
            {_played, state} = Output.fence_output(state)
            {:noreply, state} = Output.admit_next_pending(state)
            {:reply, :ok, %{state | external_activity_origin: nil}}

          {:error, _reason} ->
            Output.stop_unavailable(:provider_failed, state)
        end

      {:error, _reason} ->
        Output.stop_unavailable(:provider_failed, state)
    end
  end

  def hold(state) do
    state = Input.hold(state)
    state = %{state | origin_lifecycle_revision: make_ref(), input_turns: MapSet.new()}
    state = state |> interrupt_tool_turns() |> ToolEvents.retire()

    case Output.retire_stale_pending(state) do
      {:ok, state} ->
        {_played, state} = Output.fence_output(state)

        if Input.input_quiescent?(state) do
          {:noreply, state} =
            if state.descriptor.response_start?,
              do: Output.admit_next_pending(state),
              else: {:noreply, state}

          {:reply, :ok, %{state | external_activity_origin: nil}}
        else
          Output.stop_unavailable(:unsafe_hold, state)
        end

      {:error, _reason} ->
        Output.stop_unavailable(:provider_failed, state)
    end
  end

  def release(%{descriptor: %{hold: :mute}} = state, epoch) when is_reference(epoch) do
    case Session.set_input_hold(state.session, false) do
      :ok -> release_input(state, epoch, false)
      {:error, _reason} -> Output.stop_unavailable(:provider_failed, state)
    end
  end

  def release(state, epoch) when is_reference(epoch), do: release_input(state, epoch, true)

  defp release_input(state, epoch, rotate_origin?) do
    case Input.release(state, epoch) do
      {:ok, state} ->
        state = %{state | input_turns: MapSet.new()}

        state =
          if rotate_origin?, do: %{state | origin_lifecycle_revision: make_ref()}, else: state

        case Output.retire_stale_pending(state) do
          {:ok, state} ->
            {:noreply, state} = Output.admit_next_pending(state)
            {:reply, :ok, state}

          {:error, _reason} ->
            Output.stop_unavailable(:provider_failed, state)
        end

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  defp interrupt_tool_turns(state) do
    Enum.each(state.tool_turns, &Output.interrupt_provider(state, &1))
    state
  end
end
