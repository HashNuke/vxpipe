defmodule Vxpipe.CallEngine.CallSpec.Participant do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.{
    Capabilities,
    ConnectionIntent,
    MediaPolicy,
    ToolSelection,
    TransferHistory,
    VariablePermissions
  }

  alias Vxpipe.CallEngine.CallSpecValidation

  @all_fields [
    :type,
    :description,
    :connection,
    :transfer_notice,
    :prompt,
    :first_message,
    :capabilities,
    :while_present,
    :tools,
    :transfers,
    :transfer_history,
    :variable_permissions
  ]
  @human_fields [
    :type,
    :description,
    :connection,
    :transfer_notice,
    :capabilities,
    :while_present
  ]
  @agent_fields [
    :type,
    :description,
    :prompt,
    :first_message,
    :capabilities,
    :while_present,
    :tools,
    :transfers,
    :transfer_history,
    :variable_permissions
  ]

  @enforce_keys [
    :call_spec_key,
    :kind,
    :description,
    :connection,
    :transfer_notice,
    :prompt,
    :first_message,
    :first_message_text,
    :capabilities,
    :while_present,
    :tools,
    :transfers,
    :transfer_history,
    :variable_permissions
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          call_spec_key: String.t(),
          kind: :human | :agent,
          description: nil | String.t(),
          connection: nil | ConnectionIntent.t(),
          transfer_notice: nil | String.t(),
          prompt: nil | String.t(),
          first_message: nil | :wait_for_input | :generated | :fixed,
          first_message_text: nil | String.t(),
          capabilities: Capabilities.t(),
          while_present: MediaPolicy.t(),
          tools: %{optional(String.t()) => ToolSelection.t()},
          transfers: [String.t()],
          transfer_history: nil | TransferHistory.t(),
          variable_permissions: VariablePermissions.t()
        }

  def new(call_spec_key, value) do
    code = :invalid_call_spec
    message = "The call spec is invalid."
    path = ["participants", call_spec_key]

    with {:ok, call_spec_key} <-
           CallSpecValidation.identifier(call_spec_key, code, message, path),
         {:ok, input} <-
           CallSpecValidation.normalize_map(value, @all_fields, code, message, path),
         {:ok, type_input} <- CallSpecValidation.fetch(input, :type, code, message, path),
         {:ok, kind} <-
           CallSpecValidation.enum(
             type_input,
             [human: "human", agent: "agent"],
             code,
             message,
             path ++ ["type"]
           ),
         :ok <- reject_kind_fields(input, kind, code, message, path),
         {:ok, description} <- optional_description(input, code, message, path),
         {:ok, capabilities} <-
           Capabilities.new(Map.get(input, :capabilities, %{}), path ++ ["capabilities"]),
         {:ok, while_present} <-
           MediaPolicy.from_optional(
             Map.fetch(input, :while_present),
             path ++ ["while_present"]
           ),
         {:ok, attributes} <- kind_attributes(kind, input, code, message, path) do
      {:ok,
       struct!(
         __MODULE__,
         Map.merge(attributes, %{
           call_spec_key: call_spec_key,
           kind: kind,
           description: description,
           capabilities: capabilities,
           while_present: while_present
         })
       )}
    end
  end

  defp reject_kind_fields(input, kind, code, message, path) do
    allowed = if kind == :human, do: @human_fields, else: @agent_fields

    case Enum.find(Map.keys(input), &(&1 not in allowed)) do
      nil ->
        :ok

      field ->
        CallSpecValidation.invalid(
          code,
          message,
          path ++ [Atom.to_string(field)],
          "is not supported for this participant type"
        )
    end
  end

  defp optional_description(input, code, message, path) do
    CallSpecValidation.optional_string(
      Map.get(input, :description),
      code,
      message,
      path ++ ["description"],
      maximum: 1_024
    )
  end

  defp kind_attributes(:human, input, code, message, path) do
    with {:ok, connection_input} <-
           CallSpecValidation.fetch(input, :connection, code, message, path),
         {:ok, connection} <- ConnectionIntent.new(connection_input, path ++ ["connection"]),
         {:ok, transfer_notice} <-
           CallSpecValidation.optional_string(
             Map.get(input, :transfer_notice),
             code,
             message,
             path ++ ["transfer_notice"],
             maximum: 4_096
           ) do
      {:ok,
       %{
         connection: connection,
         transfer_notice: transfer_notice,
         prompt: nil,
         first_message: nil,
         first_message_text: nil,
         tools: %{},
         transfers: [],
         transfer_history: nil,
         variable_permissions: %VariablePermissions{}
       }}
    end
  end

  defp kind_attributes(:agent, input, code, message, path) do
    with {:ok, prompt_input} <- CallSpecValidation.fetch(input, :prompt, code, message, path),
         {:ok, prompt} <-
           CallSpecValidation.string(prompt_input, code, message, path ++ ["prompt"],
             maximum: 32_768
           ),
         {:ok, first_message, first_message_text} <-
           first_message(
             Map.get(input, :first_message, %{"mode" => "wait_for_input"}),
             code,
             message,
             path
           ),
         {:ok, tools} <- tools(Map.get(input, :tools, %{}), code, message, path),
         {:ok, transfers} <- transfers(Map.get(input, :transfers, []), code, message, path),
         {:ok, transfer_history} <-
           TransferHistory.new(Map.get(input, :transfer_history), path ++ ["transfer_history"]),
         {:ok, variable_permissions} <-
           VariablePermissions.new(
             Map.get(input, :variable_permissions, %{}),
             path ++ ["variable_permissions"]
           ) do
      {:ok,
       %{
         connection: nil,
         transfer_notice: nil,
         prompt: prompt,
         first_message: first_message,
         first_message_text: first_message_text,
         tools: tools,
         transfers: transfers,
         transfer_history: transfer_history,
         variable_permissions: variable_permissions
       }}
    end
  end

  defp first_message(value, code, message, path) do
    first_path = path ++ ["first_message"]

    with {:ok, input} <-
           CallSpecValidation.normalize_map(value, [:mode, :text], code, message, first_path),
         {:ok, mode_input} <- CallSpecValidation.fetch(input, :mode, code, message, first_path),
         {:ok, mode} <-
           CallSpecValidation.enum(
             mode_input,
             [wait_for_input: "wait_for_input", generated: "generated", fixed: "fixed"],
             code,
             message,
             first_path ++ ["mode"]
           ) do
      first_message_text(mode, input, code, message, first_path)
    end
  end

  defp first_message_text(:fixed, input, code, message, path) do
    with {:ok, text_input} <- CallSpecValidation.fetch(input, :text, code, message, path),
         {:ok, text} <-
           CallSpecValidation.string(text_input, code, message, path ++ ["text"], maximum: 4_096) do
      {:ok, :fixed, text}
    end
  end

  defp first_message_text(mode, input, code, message, path) do
    if Map.has_key?(input, :text) do
      CallSpecValidation.invalid(
        code,
        message,
        path ++ ["text"],
        "is only supported for fixed mode"
      )
    else
      {:ok, mode, nil}
    end
  end

  defp tools(value, _code, _message, path) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {name, definition}, {:ok, tools} ->
      tool_path = path ++ ["tools", if(is_binary(name), do: name, else: "<invalid-key>")]

      case ToolSelection.new(name, definition, tool_path) do
        {:ok, selection} -> {:cont, {:ok, Map.put(tools, selection.name, selection)}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp tools(_value, code, message, path) do
    CallSpecValidation.invalid(code, message, path ++ ["tools"], "must be an object")
  end

  defp transfers(value, code, message, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {target, index}, {:ok, targets, seen} ->
      target_path = path ++ ["transfers", Integer.to_string(index)]

      case CallSpecValidation.identifier(target, code, message, target_path) do
        {:ok, target} ->
          if MapSet.member?(seen, target) do
            {:halt,
             CallSpecValidation.invalid(code, message, target_path, "must not be duplicated")}
          else
            {:cont, {:ok, [target | targets], MapSet.put(seen, target)}}
          end

        {:error, _error} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, targets, _seen} -> {:ok, Enum.reverse(targets)}
      {:error, _error} = error -> error
    end
  end

  defp transfers(_value, code, message, path) do
    CallSpecValidation.invalid(
      code,
      message,
      path ++ ["transfers"],
      "must be an array of participant references"
    )
  end
end
