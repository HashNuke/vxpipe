defmodule Vxpipe.CallEngine.TestFluxCloseProbe.Evidence do
  @moduledoc false

  @derive {Inspect, only: [:terminal]}
  defstruct [
    :expected_tail,
    :deadline,
    :request_id,
    :terminal,
    sequence: -1,
    last_turn: -1,
    turns: %{},
    connected?: false,
    audio_sent?: false,
    close_stream_sent?: false,
    error_free?: true
  ]

  def new(tail, deadline), do: %__MODULE__{expected_tail: tail, deadline: deadline}

  def accept(state, event, now) do
    cond do
      state.terminal != nil -> state
      now >= state.deadline -> fail(state, :timeout)
      true -> apply_event(state, event)
    end
  end

  def fail(state, terminal), do: %{state | terminal: terminal}

  def report(state) do
    tail? = tail_verified?(state)

    %{
      terminal: state.terminal,
      connected?: state.connected?,
      audio_sent?: state.audio_sent?,
      close_stream_sent?: state.close_stream_sent?,
      tail_verified?: tail?,
      error_free?: state.error_free?,
      passed?:
        state.terminal == :normal_or_no_status and state.connected? and
          state.audio_sent? and state.close_stream_sent? and state.error_free? and tail?
    }
  end

  defp apply_event(state, {:signal, %{kind: :failed}}),
    do: %{state | terminal: :provider_error, error_free?: false}

  defp apply_event(state, {:signal, %{kind: :connected} = signal}) do
    if state.connected? do
      fail(state, :invalid_order)
    else
      %{
        state
        | connected?: true,
          request_id: signal.request_id,
          sequence: signal.provider_sequence
      }
    end
  end

  defp apply_event(state, {:signal, signal}) do
    if state.connected? and signal.request_id == state.request_id and
         signal.provider_sequence > state.sequence and
         signal.provider_turn_index >= state.last_turn do
      retain_turn(state, signal)
    else
      fail(state, :invalid_order)
    end
  end

  defp apply_event(state, {:peer_close, :normal_or_no_status, true}) do
    if state.close_stream_sent?,
      do: fail(state, :normal_or_no_status),
      else: fail(state, :early_peer_close)
  end

  defp apply_event(state, {:peer_close, _, false}), do: fail(state, :early_peer_close)
  defp apply_event(state, {:peer_close, _, true}), do: fail(state, :abnormal_peer_close)

  defp apply_event(state, :invalid_wire),
    do: %{state | terminal: :invalid_wire, error_free?: false}

  defp apply_event(state, terminal) when terminal in [:connection_lost, :limit],
    do: fail(state, terminal)

  defp retain_turn(state, signal) do
    turns = Map.put(state.turns, signal.provider_turn_index, signal.text)

    bytes =
      Enum.reduce(turns, max(map_size(turns) - 1, 0), fn {_, text}, sum ->
        sum + byte_size(text)
      end)

    if map_size(turns) > 16 or bytes > 65_536 do
      fail(state, :limit)
    else
      %{
        state
        | turns: turns,
          sequence: signal.provider_sequence,
          last_turn: signal.provider_turn_index
      }
    end
  end

  defp tail_verified?(state) do
    text = state.turns |> Enum.sort_by(&elem(&1, 0)) |> Enum.map_join(" ", &elem(&1, 1))
    is_binary(state.expected_tail) and String.ends_with?(text, state.expected_tail)
  end
end
