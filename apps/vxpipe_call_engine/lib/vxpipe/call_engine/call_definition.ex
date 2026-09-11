defmodule Vxpipe.CallEngine.CallDefinition do
  @moduledoc """
  A validated, versioned definition of reusable call behavior.
  """

  alias Vxpipe.CallEngine.CallDefinition.{
    CallVariables,
    Capabilities,
    MediaPolicy,
    OpeningAudio,
    Participant,
    TransferPolicy,
    ToolVisibility
  }

  alias Vxpipe.CallEngine.DefinitionValidation

  @schema_version "20260911.01"
  @fields [
    :schema_version,
    :name,
    :entry_caller,
    :entry_receiver,
    :defaults,
    :opening_audio,
    :media_policy,
    :call_variables,
    :participants,
    :transfer_policy,
    :tool_visibility,
    :tool_visibility_overrides,
    :limits
  ]

  @enforce_keys [
    :resource_id,
    :revision,
    :schema_version,
    :name,
    :entry_caller,
    :entry_receiver,
    :default_capabilities,
    :opening_audio,
    :media_policy,
    :call_variables,
    :participants,
    :transfer_policy,
    :tool_visibility,
    :max_duration_ms
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          resource_id: String.t(),
          revision: pos_integer(),
          schema_version: String.t(),
          name: nil | String.t(),
          entry_caller: String.t(),
          entry_receiver: String.t(),
          default_capabilities: Capabilities.t(),
          opening_audio: nil | OpeningAudio.t(),
          media_policy: MediaPolicy.t(),
          call_variables: CallVariables.t(),
          participants: %{String.t() => Participant.t()},
          transfer_policy: TransferPolicy.t(),
          tool_visibility: ToolVisibility.t(),
          max_duration_ms: nil | pos_integer()
        }

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def new(value, options) when is_list(options) do
    code = :invalid_call_definition
    message = "The call definition is invalid."

    with {:ok, resource_id_input} <- trusted_option(options, :resource_id, code, message),
         {:ok, resource_id} <-
           DefinitionValidation.identifier(resource_id_input, code, message, ["resource_id"]),
         {:ok, revision_input} <- trusted_option(options, :revision, code, message),
         {:ok, revision} <-
           DefinitionValidation.positive_integer(revision_input, code, message, ["revision"]),
         {:ok, input} <- DefinitionValidation.normalize_map(value, @fields, code, message, []),
         {:ok, schema_input} <-
           DefinitionValidation.fetch(input, :schema_version, code, message, []),
         :ok <- validate_schema(schema_input, code, message),
         {:ok, name} <- optional_name(input, code, message),
         {:ok, caller_input} <-
           DefinitionValidation.fetch(input, :entry_caller, code, message, []),
         {:ok, entry_caller} <-
           DefinitionValidation.identifier(caller_input, code, message, ["entry_caller"]),
         {:ok, receiver_input} <-
           DefinitionValidation.fetch(input, :entry_receiver, code, message, []),
         {:ok, entry_receiver} <-
           DefinitionValidation.identifier(receiver_input, code, message, ["entry_receiver"]),
         {:ok, defaults} <- defaults(Map.get(input, :defaults, %{}), code, message),
         {:ok, opening_audio} <- OpeningAudio.new(Map.get(input, :opening_audio)),
         {:ok, media_policy} <-
           MediaPolicy.from_optional(Map.fetch(input, :media_policy), ["media_policy"]),
         {:ok, call_variables} <- CallVariables.new(Map.get(input, :call_variables, %{})),
         {:ok, participants_input} <-
           DefinitionValidation.fetch(input, :participants, code, message, []),
         {:ok, participants} <- participants(participants_input, code, message),
         :ok <- validate_entries(entry_caller, entry_receiver, participants, code, message),
         :ok <- validate_transfers(participants, code, message),
         :ok <- validate_media_policies(media_policy, participants),
         {:ok, transfer_policy} <- TransferPolicy.new(Map.get(input, :transfer_policy)),
         :ok <- validate_variable_permissions(participants, call_variables, code, message),
         {:ok, tool_visibility} <-
           ToolVisibility.new(
             Map.get(input, :tool_visibility, "hidden"),
             Map.get(input, :tool_visibility_overrides, %{}),
             participants
           ),
         {:ok, max_duration_ms} <- limits(Map.get(input, :limits, %{}), code, message) do
      {:ok,
       %__MODULE__{
         resource_id: resource_id,
         revision: revision,
         schema_version: @schema_version,
         name: name,
         entry_caller: entry_caller,
         entry_receiver: entry_receiver,
         default_capabilities: defaults,
         opening_audio: opening_audio,
         media_policy: media_policy,
         call_variables: call_variables,
         participants: participants,
         transfer_policy: transfer_policy,
         tool_visibility: tool_visibility,
         max_duration_ms: max_duration_ms
       }}
    end
  end

  @spec from_json(binary(), keyword()) :: {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def from_json(json, options) when is_binary(json) and is_list(options) do
    case JSON.decode(json) do
      {:ok, value} -> new(value, options)
      {:error, _reason} -> invalid([], "must be valid JSON")
    end
  end

  defp trusted_option(options, key, code, message) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> {:ok, value}
      :error -> DefinitionValidation.invalid(code, message, [Atom.to_string(key)], "is required")
    end
  end

  defp validate_schema(@schema_version, _code, _message), do: :ok

  defp validate_schema(_value, code, message) do
    DefinitionValidation.invalid(
      code,
      message,
      ["schema_version"],
      "must be a supported schema version"
    )
  end

  defp optional_name(input, code, message) do
    DefinitionValidation.optional_string(
      Map.get(input, :name),
      code,
      message,
      ["name"],
      maximum: 256
    )
  end

  defp defaults(value, code, message) do
    with {:ok, input} <-
           DefinitionValidation.normalize_map(value, [:capabilities], code, message, ["defaults"]),
         {:ok, capabilities} <-
           Capabilities.new(Map.get(input, :capabilities, %{}), ["defaults", "capabilities"]) do
      {:ok, capabilities}
    end
  end

  defp participants(value, code, message) when is_map(value) and map_size(value) > 0 do
    Enum.reduce_while(value, {:ok, %{}}, fn
      {key, participant_input}, {:ok, participants} when is_binary(key) ->
        case Participant.new(key, participant_input) do
          {:ok, participant} -> {:cont, {:ok, Map.put(participants, key, participant)}}
          {:error, _error} = error -> {:halt, error}
        end

      {_key, _participant_input}, _acc ->
        {:halt,
         DefinitionValidation.invalid(
           code,
           message,
           ["participants", "<invalid-key>"],
           "participant names must be strings"
         )}
    end)
  end

  defp participants(_value, code, message) do
    DefinitionValidation.invalid(code, message, ["participants"], "must be a non-empty object")
  end

  defp validate_entries(caller, receiver, participants, code, message) do
    cond do
      not Map.has_key?(participants, caller) ->
        DefinitionValidation.invalid(
          code,
          message,
          ["entry_caller"],
          "must reference a participant"
        )

      not Map.has_key?(participants, receiver) ->
        DefinitionValidation.invalid(
          code,
          message,
          ["entry_receiver"],
          "must reference a participant"
        )

      caller == receiver ->
        DefinitionValidation.invalid(
          code,
          message,
          ["entry_receiver"],
          "must differ from entry_caller"
        )

      participants[caller].kind != :human ->
        DefinitionValidation.invalid(
          code,
          message,
          ["entry_caller"],
          "must reference a human participant"
        )

      participants[receiver].kind != :agent ->
        DefinitionValidation.invalid(
          code,
          message,
          ["entry_receiver"],
          "must reference an agent participant in this schema subset"
        )

      true ->
        :ok
    end
  end

  defp limits(value, code, message) do
    with {:ok, input} <-
           DefinitionValidation.normalize_map(value, [:max_duration_ms], code, message, ["limits"]),
         {:ok, duration} <- duration(input, code, message) do
      {:ok, duration}
    end
  end

  defp validate_transfers(participants, code, message) do
    participants
    |> Enum.sort_by(fn {definition_key, _participant} -> definition_key end)
    |> Enum.reduce_while(:ok, fn {_definition_key, participant}, :ok ->
      case validate_transfer_targets(participant, participants, code, message) do
        :ok -> {:cont, :ok}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp validate_media_policies(media_policy, participants) do
    with :ok <- MediaPolicy.validate_references(media_policy, participants, ["media_policy"]) do
      Enum.reduce_while(participants, :ok, fn {definition_key, participant}, :ok ->
        case MediaPolicy.validate_references(
               participant.while_present,
               participants,
               ["participants", definition_key, "while_present"]
             ) do
          :ok -> {:cont, :ok}
          {:error, _error} = error -> {:halt, error}
        end
      end)
    end
  end

  defp validate_transfer_targets(participant, participants, code, message) do
    participant.transfers
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {target, index}, :ok ->
      path = ["participants", participant.definition_key, "transfers", Integer.to_string(index)]

      result =
        case Map.fetch(participants, target) do
          :error ->
            DefinitionValidation.invalid(code, message, path, "must reference a participant")

          {:ok, _destination} when target == participant.definition_key ->
            DefinitionValidation.invalid(
              code,
              message,
              path,
              "must reference another participant"
            )

          {:ok, %{kind: :agent}} ->
            :ok

          {:ok, _destination} ->
            DefinitionValidation.invalid(
              code,
              message,
              path,
              "must reference an agent participant in this schema subset"
            )
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp validate_variable_permissions(participants, call_variables, code, message) do
    Enum.reduce_while(participants, :ok, fn {_key, participant}, :ok ->
      result =
        Enum.reduce_while(
          participant.variable_permissions.grants,
          :ok,
          fn {section, _grant}, :ok ->
            if Map.has_key?(call_variables.sections, section) do
              {:cont, :ok}
            else
              {:halt,
               DefinitionValidation.invalid(
                 code,
                 message,
                 [
                   "participants",
                   participant.definition_key,
                   "variable_permissions",
                   section
                 ],
                 "must reference a declared Call Variables section"
               )}
            end
          end
        )

      case result do
        :ok -> {:cont, :ok}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp duration(input, code, message) do
    case Map.fetch(input, :max_duration_ms) do
      :error ->
        {:ok, nil}

      {:ok, value} when is_integer(value) and value >= 1_000 and value <= 86_400_000 ->
        {:ok, value}

      {:ok, _value} ->
        DefinitionValidation.invalid(
          code,
          message,
          ["limits", "max_duration_ms"],
          "must be between 1000 and 86400000"
        )
    end
  end

  defp invalid(path, reason) do
    DefinitionValidation.invalid(
      :invalid_call_definition,
      "The call definition is invalid.",
      path,
      reason
    )
  end
end
