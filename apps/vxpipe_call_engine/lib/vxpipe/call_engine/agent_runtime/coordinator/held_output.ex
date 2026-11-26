defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.HeldOutput do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.State

  @enforce_keys [:command, :correlation, :predecessor]
  defstruct @enforce_keys ++ [texts: [], continuation_started?: false, final: nil]

  def start(%State{current: nil} = state, _pending), do: state

  def start(state, pending) do
    held = %__MODULE__{
      command: state.current.command,
      correlation: state.current.correlation,
      predecessor: pending.command
    }

    %{state | held_output: held}
  end

  def push_text(held, text), do: %{held | texts: [text | held.texts]}

  def release(%State{held_output: nil} = state, _command, _finish), do: state

  def release(%State{held_output: held} = state, command, finish) do
    if held.predecessor == command do
      if held.continuation_started? do
        send(state.owner, {:vxpipe_capability_continuation_started, self(), held.command})
      end

      Enum.each(
        Enum.reverse(held.texts),
        &send(state.owner, {:vxpipe_capability_text, self(), held.command, &1})
      )

      state = %{state | held_output: nil}

      case held.final do
        nil ->
          state

        final ->
          case finish.(state, final) do
            {:noreply, released} -> released
            {:stop, _, _} = stop -> stop
          end
      end
    else
      state
    end
  end
end
