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

  defp waiting?(%{speech_to_text: %{turn: turn}}, _agent, _text) when not is_nil(turn), do: true
  defp waiting?(%{caller_prompt: {agent, true, _}}, agent, _text), do: true

  defp waiting?(%{caller_prompt: {agent, false, previous}}, agent, text),
    do: digest(text) == previous

  defp waiting?(_connection, _agent, _text), do: false

  defp question?(text), do: Regex.match?(~r/[?？؟፧⁇⁈⁉][\s\p{Pe}\p{Pf}"'!]*$|՞/u, text)

  defp digest(text) do
    normalized = text |> String.normalize(:nfc) |> String.downcase() |> String.trim()
    :crypto.hash(:sha256, normalized)
  end
end
