defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.OutputTranscript do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Output

  @default_timeout_ms 5_000
  @maximum_timeout_ms 30_000

  def timeout_ms(options) do
    case Keyword.get(options, :output_transcript_timeout_ms, @default_timeout_ms) do
      timeout when is_integer(timeout) and timeout > 0 and timeout <= @maximum_timeout_ms ->
        {:ok, timeout}

      _invalid ->
        {:error, :invalid_output_transcript_timeout}
    end
  end

  def accept(
        event,
        %{output_stt: nil, active_output: %{provider_turn: turn, text_final?: false} = output} =
          state
      )
      when turn == event.turn_ref do
    if expired?(output),
      do: Output.stop_unavailable(:output_transcript_timeout, state),
      else: accept_current(event, output, state)
  end

  def accept(_event, state), do: {:noreply, state}

  defp accept_current(event, output, state) do
    final? = state.descriptor.output_settlement == :transcript_end and event.final == true
    output = %{output | pending_text: event.text, text_final?: final?}

    output =
      if final? and output.text_deadline != nil do
        Process.cancel_timer(output.text_deadline)
        %{output | text_deadline: nil}
      else
        output
      end

    Output.maybe_finish_turn(%{state | active_output: output})
  end

  def acknowledge_generation(state) do
    output = %{state.active_output | generation_done?: true}

    output =
      cond do
        state.output_stt != nil ->
          output

        state.descriptor.output_settlement == :generation_boundary ->
          %{output | text_final?: is_binary(output.pending_text)}

        output.text_final? or output.text_deadline != nil ->
          output

        true ->
          expires = System.monotonic_time(:millisecond) + state.output_transcript_timeout_ms

          timer =
            Process.send_after(
              self(),
              {:vxpipe_output_transcript_timeout, output.output.ref},
              state.output_transcript_timeout_ms
            )

          %{output | text_deadline: timer, text_expires_at: expires}
      end

    %{state | active_output: output}
  end

  def generated(%{output_stt: nil, active_output: output} = state) do
    cond do
      state.descriptor.output_settlement == :generation_boundary and not ready?(output) ->
        Output.stop_unavailable(:output_transcript_missing, state)

      expired?(output) ->
        Output.stop_unavailable(:output_transcript_timeout, state)

      true ->
        Output.maybe_finish_turn(state)
    end
  end

  def generated(state), do: Output.maybe_finish_turn(state)

  def expire(
        ref,
        %{
          output_stt: nil,
          active_output: %{output: %{ref: ref}, generation_done?: true, text_final?: false}
        } = state
      ),
      do: Output.stop_unavailable(:output_transcript_timeout, state)

  def expire(_ref, state), do: {:noreply, state}

  def ready?(output), do: output.text_final? and is_binary(output.pending_text)

  defp expired?(%{text_final?: false, text_expires_at: deadline}) when is_integer(deadline),
    do: System.monotonic_time(:millisecond) >= deadline

  defp expired?(_output), do: false
end
