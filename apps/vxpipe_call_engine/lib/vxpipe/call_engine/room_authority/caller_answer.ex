defmodule Vxpipe.CallEngine.RoomAuthority.CallerAnswer do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables.Binding
  alias Vxpipe.CallEngine.Command.ContinueAgent

  # The connection owns delivery evidence until its caller's next accepted input.
  # Keep only a digest of the most recently delivered segment. Question marks also
  # reserve the floor for an answer when the model rephrases a form question.
  def delivered(%{text_capability: %{pid: agent}} = state, command, text) do
    connections =
      Map.replace_lazy(state.connections, command.connection_id, fn connection ->
        outstanding? = match?(%{caller_prompt: {^agent, true, _}}, connection)
        prompt = {agent, outstanding? or question?(text), digest(text)}
        Map.put(connection, :caller_prompt, prompt)
      end)

    %{state | connections: connections}
  end

  def delivered(state, _command, _text), do: state

  def accepted(state, command) do
    connections =
      Map.replace_lazy(state.connections, command.connection_id, &Map.delete(&1, :caller_prompt))

    %{state | connections: connections}
  end

  def output_allowed?(%ContinueAgent{tool_name: name}, connection, agent, text) do
    not (Binding.variable_tool?(name) and waiting?(connection, agent, text))
  end

  def output_allowed?(_command, _connection, _agent, _text), do: true

  @doc """
  Admission for engine-proposed terminal actions (`hangup` and participant
  transfer tool bindings).

  Returns `:ok` unless the request runs in an engine-origin turn while the
  caller's answer is still outstanding (a delivered question not yet answered,
  a question already playing/queued on the voice path, or an active STT turn).

  Origin is explicit and trusted: `ActiveRequest` marks caller turns `:caller`
  and greeting/idle turns `:engine`; `CompletionContinuation` marks tool-result
  continuations `:engine`; native STS turns carry `:sts`. Caller and STS turns
  keep their explicitly requested goodbye and transfer. Unknown turns fail
  closed while a prompt is outstanding.
  """
  @spec terminal_admission(map(), map()) :: :ok | {:error, :caller_answer_pending}
  def terminal_admission(state, context) do
    case Map.get(context, :request_origin) do
      :caller ->
        :ok

      :sts ->
        :ok

      _engine_or_unknown ->
        if answer_pending?(state, context) do
          {:error, :caller_answer_pending}
        else
          :ok
        end
    end
  end

  defp waiting?(%{speech_to_text: %{turn: turn}}, _agent, _text) when not is_nil(turn), do: true
  defp waiting?(%{caller_prompt: {agent, true, _}}, agent, _text), do: true

  defp waiting?(%{caller_prompt: {agent, false, previous}}, agent, text),
    do: digest(text) == previous

  defp waiting?(_connection, _agent, _text), do: false

  defp answer_pending?(state, context) do
    connections = Map.get(state, :connections, %{})
    connection_id = Map.get(context, :connection_id)
    connection = Map.get(connections, connection_id, %{})

    prompt_pending?(connection, agent_pid(state)) or stt_active?(connection) or
      playing_question?(state, connection_id)
  end

  defp agent_pid(state) do
    case Map.get(state, :text_capability) do
      %{pid: pid} when not is_nil(pid) -> pid
      _unavailable -> nil
    end
  end

  defp prompt_pending?(_connection, nil), do: false

  defp prompt_pending?(connection, agent) do
    match?(%{caller_prompt: {^agent, true, _}}, connection)
  end

  defp stt_active?(connection) do
    match?(%{speech_to_text: %{turn: turn}} when not is_nil(turn), connection)
  end

  # A question already playing on the voice path reserves the floor even before
  # its delivery receipt confirms it. Silent or settled turns never block.
  defp playing_question?(state, connection_id) when is_binary(connection_id) do
    state
    |> Map.get(:agent_turns, %{})
    |> Map.values()
    |> Enum.any?(fn turn ->
      turn_connection_id(turn) == connection_id and unconfirmed_question?(turn)
    end)
  end

  defp playing_question?(_state, _connection_id), do: false

  defp turn_connection_id(turn) do
    case Map.get(turn, :command) do
      %{connection_id: connection_id} -> connection_id
      _unmatched -> nil
    end
  end

  defp unconfirmed_question?(turn) do
    requests = Map.get(turn, :speech_requests, %{})

    map_size(requests) > 0 and
      Enum.any?(requests, fn {_id, request} ->
        text = Map.get(request, :text)
        is_binary(text) and question?(text)
      end)
  end

  defp question?(text), do: Regex.match?(~r/[?？؟፧⁇⁈⁉][\s\p{Pe}\p{Pf}"'!]*$|՞/u, text)

  defp digest(text) do
    normalized = text |> String.normalize(:nfc) |> String.downcase() |> String.trim()
    :crypto.hash(:sha256, normalized)
  end
end
