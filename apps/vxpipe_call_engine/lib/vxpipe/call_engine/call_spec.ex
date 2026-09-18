defmodule Vxpipe.CallEngine.CallSpec do
  @moduledoc """
  A validated, versioned call spec of reusable call behavior.
  """

  alias Vxpipe.CallEngine.CallSpec.{
    CallVariables,
    Capabilities,
    MediaPolicy,
    OpeningAudio,
    Participant,
    TransferPolicy,
    ToolVisibility,
    WaitSounds
  }

  alias Vxpipe.CallEngine.CallSpecValidation

  @schema_version "20260915.01"
  @fields [
    :schema_version,
    :name,
    :entry_caller,
    :entry_receiver,
    :defaults,
    :opening_audio,
    :wait_sounds,
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
  defstruct @enforce_keys ++ [wait_sounds: %WaitSounds{}]

  @type t :: %__MODULE__{
          resource_id: String.t(),
          revision: pos_integer(),
          schema_version: String.t(),
          name: nil | String.t(),
          entry_caller: String.t(),
          entry_receiver: String.t(),
          default_capabilities: Capabilities.t(),
          opening_audio: nil | OpeningAudio.t(),
          wait_sounds: WaitSounds.t(),
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
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with {:ok, resource_id_input} <- trusted_option(options, :resource_id, code, message),
         {:ok, resource_id} <-
           CallSpecValidation.identifier(resource_id_input, code, message, ["resource_id"]),
         {:ok, revision_input} <- trusted_option(options, :revision, code, message),
         {:ok, revision} <-
           CallSpecValidation.positive_integer(revision_input, code, message, ["revision"]),
         {:ok, input} <- CallSpecValidation.normalize_map(value, @fields, code, message, []),
         {:ok, schema_input} <-
           CallSpecValidation.fetch(input, :schema_version, code, message, []),
         :ok <- validate_schema(schema_input, code, message),
         {:ok, name} <- optional_name(input, code, message),
         {:ok, caller_input} <-
           CallSpecValidation.fetch(input, :entry_caller, code, message, []),
         {:ok, entry_caller} <-
           CallSpecValidation.identifier(caller_input, code, message, ["entry_caller"]),
         {:ok, receiver_input} <-
           CallSpecValidation.fetch(input, :entry_receiver, code, message, []),
         {:ok, entry_receiver} <-
           CallSpecValidation.identifier(receiver_input, code, message, ["entry_receiver"]),
         {:ok, defaults} <- defaults(Map.get(input, :defaults, %{}), code, message),
         {:ok, opening_audio} <- OpeningAudio.new(Map.get(input, :opening_audio)),
         {:ok, wait_sounds} <- WaitSounds.from_optional(Map.fetch(input, :wait_sounds)),
         {:ok, media_policy} <-
           MediaPolicy.from_optional(Map.fetch(input, :media_policy), ["media_policy"]),
         {:ok, call_variables} <- CallVariables.new(Map.get(input, :call_variables, %{})),
         {:ok, participants_input} <-
           CallSpecValidation.fetch(input, :participants, code, message, []),
         {:ok, participants} <- participants(participants_input, code, message),
         :ok <- validate_entries(entry_caller, entry_receiver, participants, code, message),
         :ok <- validate_transfers(participants, code, message),
         :ok <- validate_media_policies(media_policy, participants),
         {:ok, transfer_policy} <- TransferPolicy.new(Map.get(input, :transfer_policy)),
         :ok <- validate_variable_permissions(participants, call_variables, code, message),
         :ok <- validate_dial_destinations(participants, call_variables, code, message),
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
         schema_version: schema_input,
         name: name,
         entry_caller: entry_caller,
         entry_receiver: entry_receiver,
         default_capabilities: defaults,
         opening_audio: opening_audio,
         wait_sounds: wait_sounds,
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
      :error -> CallSpecValidation.invalid(code, message, [Atom.to_string(key)], "is required")
    end
  end

  defp validate_schema(@schema_version, _code, _message), do: :ok

  defp validate_schema(_value, code, message) do
    CallSpecValidation.invalid(
      code,
      message,
      ["schema_version"],
      "must be a supported schema version"
    )
  end

  defp optional_name(input, code, message) do
    CallSpecValidation.optional_string(
      Map.get(input, :name),
      code,
      message,
      ["name"],
      maximum: 256
    )
  end

  defp defaults(value, code, message) do
    with {:ok, input} <-
           CallSpecValidation.normalize_map(value, [:capabilities], code, message, ["defaults"]),
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
         CallSpecValidation.invalid(
           code,
           message,
           ["participants", "<invalid-key>"],
           "participant names must be strings"
         )}
    end)
  end

  defp participants(_value, code, message) do
    CallSpecValidation.invalid(code, message, ["participants"], "must be a non-empty object")
  end

  defp validate_entries(caller, receiver, participants, code, message) do
    cond do
      not Map.has_key?(participants, caller) ->
        CallSpecValidation.invalid(
          code,
          message,
          ["entry_caller"],
          "must reference a participant"
        )

      not Map.has_key?(participants, receiver) ->
        CallSpecValidation.invalid(
          code,
          message,
          ["entry_receiver"],
          "must reference a participant"
        )

      caller == receiver ->
        CallSpecValidation.invalid(
          code,
          message,
          ["entry_receiver"],
          "must differ from entry_caller"
        )

      participants[caller].kind != :human ->
        CallSpecValidation.invalid(
          code,
          message,
          ["entry_caller"],
          "must reference a human participant"
        )

      true ->
        :ok
    end
  end

  defp limits(value, code, message) do
    with {:ok, input} <-
           CallSpecValidation.normalize_map(value, [:max_duration_ms], code, message, ["limits"]),
         {:ok, duration} <- duration(input, code, message) do
      {:ok, duration}
    end
  end

  defp validate_transfers(participants, code, message) do
    participants
    |> Enum.sort_by(fn {call_spec_key, _participant} -> call_spec_key end)
    |> Enum.reduce_while(:ok, fn {_call_spec_key, participant}, :ok ->
      case validate_transfer_targets(participant, participants, code, message) do
        :ok -> {:cont, :ok}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp validate_media_policies(media_policy, participants) do
    with :ok <- MediaPolicy.validate_references(media_policy, participants, ["media_policy"]) do
      Enum.reduce_while(participants, :ok, fn {call_spec_key, participant}, :ok ->
        case MediaPolicy.validate_references(
               participant.while_present,
               participants,
               ["participants", call_spec_key, "while_present"]
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
      path = ["participants", participant.call_spec_key, "transfers", Integer.to_string(index)]

      result =
        case Map.fetch(participants, target) do
          :error ->
            CallSpecValidation.invalid(code, message, path, "must reference a participant")

          {:ok, _destination} when target == participant.call_spec_key ->
            CallSpecValidation.invalid(
              code,
              message,
              path,
              "must reference another participant"
            )

          {:ok, %{kind: :agent}} ->
            :ok

          {:ok,
           %{
             kind: :human,
             connection: %Vxpipe.CallEngine.CallSpec.ConnectionIntent{
               service: :web,
               mode: :receive,
               admission: :transfer
             }
           }} ->
            :ok

          {:ok,
           %{
             kind: :human,
             connection: %Vxpipe.CallEngine.CallSpec.ConnectionIntent{
               service: service,
               mode: :dial,
               admission: :transfer
             }
           }}
          when is_binary(service) ->
            :ok

          {:ok, _destination} ->
            CallSpecValidation.invalid(
              code,
              message,
              path,
              "must reference an agent or transfer-admission human participant"
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
               CallSpecValidation.invalid(
                 code,
                 message,
                 [
                   "participants",
                   participant.call_spec_key,
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

  defp validate_dial_destinations(participants, call_variables, code, message) do
    participants
    |> Enum.sort_by(fn {call_spec_key, _participant} -> call_spec_key end)
    |> Enum.reduce_while(:ok, fn {_key, participant}, :ok ->
      case validate_dial_destination(participant, participants, call_variables, code, message) do
        :ok -> {:cont, :ok}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp validate_dial_destination(
         %Participant{
           connection: %Vxpipe.CallEngine.CallSpec.ConnectionIntent{
             number_from_variable: %Vxpipe.CallEngine.CallSpec.NumberFromVariable{} = source
           }
         } = participant,
         participants,
         call_variables,
         code,
         message
       ) do
    path = ["participants", participant.call_spec_key, "connection", "number_from_variable"]

    with {:ok, section} <-
           fetch_dial_section(call_variables, source.section, code, message, path),
         :ok <- string_dial_variable(section.schema, source.variable, code, message, path),
         :ok <- protected_dial_section(participants, source.section, code, message) do
      :ok
    end
  end

  defp validate_dial_destination(
         %Participant{},
         _participants,
         _call_variables,
         _code,
         _message
       ),
       do: :ok

  defp fetch_dial_section(call_variables, section_name, code, message, path) do
    case Map.fetch(call_variables.sections, section_name) do
      {:ok, section} ->
        {:ok, section}

      :error ->
        CallSpecValidation.invalid(
          code,
          message,
          path ++ ["section"],
          "must reference a declared Call Variables section"
        )
    end
  end

  defp string_dial_variable(schema, variable, code, message, path) do
    case schema |> Map.get("properties", %{}) |> Map.fetch(variable) do
      {:ok, variable_schema} ->
        if string_compatible_schema?(variable_schema) do
          :ok
        else
          CallSpecValidation.invalid(
            code,
            message,
            path ++ ["variable"],
            "must reference a string-compatible Call Variable"
          )
        end

      :error ->
        CallSpecValidation.invalid(
          code,
          message,
          path ++ ["variable"],
          "must reference a declared Call Variable"
        )
    end
  end

  defp string_compatible_schema?(%{"type" => "string"}), do: true

  defp string_compatible_schema?(%{"type" => types}) when is_list(types),
    do: "string" in types

  defp string_compatible_schema?(_schema), do: false

  defp protected_dial_section(participants, section, code, message) do
    participants
    |> Enum.sort_by(fn {call_spec_key, _participant} -> call_spec_key end)
    |> Enum.find(fn {_call_spec_key, participant} ->
      participant.kind == :agent and
        Map.get(participant.variable_permissions.grants, section) == :read_write
    end)
    |> case do
      nil ->
        :ok

      {call_spec_key, _participant} ->
        CallSpecValidation.invalid(
          code,
          message,
          ["participants", call_spec_key, "variable_permissions", section],
          "must not grant write access to a dial-routing section"
        )
    end
  end

  defp duration(input, code, message) do
    case Map.fetch(input, :max_duration_ms) do
      :error ->
        {:ok, nil}

      {:ok, value} when is_integer(value) and value >= 1_000 and value <= 86_400_000 ->
        {:ok, value}

      {:ok, _value} ->
        CallSpecValidation.invalid(
          code,
          message,
          ["limits", "max_duration_ms"],
          "must be between 1000 and 86400000"
        )
    end
  end

  defp invalid(path, reason) do
    CallSpecValidation.invalid(
      :invalid_call_spec,
      "The call spec is invalid.",
      path,
      reason
    )
  end
end
