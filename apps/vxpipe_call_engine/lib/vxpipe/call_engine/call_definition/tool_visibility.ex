defmodule Vxpipe.CallEngine.CallDefinition.ToolVisibility do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.Participant
  alias Vxpipe.CallEngine.DefinitionValidation

  @levels [hidden: "hidden", metadata: "metadata", full: "full"]
  @code :invalid_call_definition
  @message "The call definition is invalid."

  @enforce_keys [:default, :overrides]
  defstruct @enforce_keys

  @type level :: :hidden | :metadata | :full
  @type t :: %__MODULE__{
          default: level(),
          overrides: %{String.t() => %{String.t() => level()}}
        }

  @spec new(term(), term(), %{String.t() => Participant.t()}) ::
          {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def new(default, overrides, participants) when is_map(participants) do
    with {:ok, default} <- level(default, ["tool_visibility"]),
         {:ok, overrides} <- overrides(overrides, participants) do
      {:ok, %__MODULE__{default: default, overrides: overrides}}
    end
  end

  defp overrides(value, participants) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn
      {participant_key, tool_levels}, {:ok, acc} when is_binary(participant_key) ->
        case participant(participant_key, participants) do
          {:ok, participant} ->
            case tool_levels(participant_key, tool_levels, participant) do
              {:ok, levels} -> {:cont, {:ok, Map.put(acc, participant_key, levels)}}
              {:error, _error} = error -> {:halt, error}
            end

          {:error, _error} = error ->
            {:halt, error}
        end

      {_participant_key, _tool_levels}, _acc ->
        {:halt,
         invalid(
           ["tool_visibility_overrides", "<invalid-key>"],
           "must reference an agent participant"
         )}
    end)
  end

  defp overrides(_value, _participants) do
    invalid(["tool_visibility_overrides"], "must be an object")
  end

  defp participant(participant_key, participants) do
    path = ["tool_visibility_overrides", participant_key]

    case Map.fetch(participants, participant_key) do
      {:ok, %Participant{kind: :agent} = participant} -> {:ok, participant}
      _missing_or_human -> invalid(path, "must reference an agent participant")
    end
  end

  defp tool_levels(participant_key, value, %Participant{} = participant) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn
      {tool_key, level_input}, {:ok, acc} when is_binary(tool_key) ->
        path = ["tool_visibility_overrides", participant_key, tool_key]

        if Map.has_key?(participant.tools, tool_key) do
          case level(level_input, path) do
            {:ok, visibility} -> {:cont, {:ok, Map.put(acc, tool_key, visibility)}}
            {:error, _error} = error -> {:halt, error}
          end
        else
          {:halt, invalid(path, "must reference a configured local tool")}
        end

      {_tool_key, _level_input}, _acc ->
        {:halt,
         invalid(
           ["tool_visibility_overrides", participant_key, "<invalid-key>"],
           "must reference a configured local tool"
         )}
    end)
  end

  defp tool_levels(participant_key, _value, _participant) do
    invalid(["tool_visibility_overrides", participant_key], "must be an object")
  end

  defp level(value, path) do
    DefinitionValidation.enum(value, @levels, @code, @message, path)
  end

  defp invalid(path, reason) do
    DefinitionValidation.invalid(@code, @message, path, reason)
  end
end
