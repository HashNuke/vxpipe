defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.OutputTranscript do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Output
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Opening

  @default_timeout_ms 5_000
  @maximum_timeout_ms 30_000
  @maximum_fragments 256
  @maximum_fragment_bytes 65_536

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

    with {:ok, output} <- add_text(output, event) do
      output = %{output | text_final?: final?}

      output =
        if final? and output.text_deadline != nil do
          Process.cancel_timer(output.text_deadline)
          %{output | text_deadline: nil}
        else
          output
        end

      Output.maybe_finish_turn(%{state | active_output: output})
    else
      :ignore -> {:noreply, state}
      {:error, :output_text_overflow} -> Output.stop_unavailable(:output_text_overflow, state)
    end
  end

  defp add_text(%{output: %{ref: ref}} = output, %{output_ref: ref} = event) do
    bytes = output.fragment_bytes + byte_size(event.text)

    if length(output.fragments) >= @maximum_fragments or bytes > @maximum_fragment_bytes do
      {:error, :output_text_overflow}
    else
      fragment = {event.audio_start_ms, event.audio_end_ms, event.text}
      {:ok, %{output | fragments: [fragment | output.fragments], fragment_bytes: bytes}}
    end
  end

  defp add_text(output, %{output_ref: nil, text: text}),
    do: {:ok, %{output | pending_text: text}}

  defp add_text(_output, _foreign_output), do: :ignore

  def text(%{fragments: [_ | _]} = output, played_ms) do
    output.fragments
    |> Enum.reverse()
    |> Enum.filter(fn {_start_ms, end_ms, _text} -> end_ms <= played_ms end)
    |> Enum.map_join("", fn {_start_ms, _end_ms, text} -> text end)
    |> case do
      "" -> nil
      text -> text
    end
  end

  def text(%{pending_text: ""}, _played_ms), do: nil
  def text(%{pending_text: text}, _played_ms), do: text

  def aligned?(%{fragments: [_ | _]}), do: true
  def aligned?(_output), do: false

  def acknowledge_generation(state) do
    output = %{state.active_output | generation_done?: true}

    output =
      cond do
        state.output_stt != nil ->
          output

        state.descriptor.output_settlement == :generation_boundary ->
          %{output | text_final?: is_binary(output.pending_text) or output.fragments != []}

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

    state = %{state | active_output: output}

    if Opening.audio_only?(state),
      do: %{state | active_output: %{output | text_final?: true}},
      else: state
  end

  def generated(%{output_stt: nil, active_output: output} = state) do
    cond do
      Opening.audio_only?(state) ->
        Output.maybe_finish_turn(state)

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

  def ready?(output),
    do: output.text_final? and (is_binary(output.pending_text) or output.fragments != [])

  defp expired?(%{text_final?: false, text_expires_at: deadline}) when is_integer(deadline),
    do: System.monotonic_time(:millisecond) >= deadline

  defp expired?(_output), do: false
end
