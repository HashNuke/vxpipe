defmodule Vxpipe.AgentRuntime.PendingInvocation do
  @moduledoc "A bounded, payload-free projection of one unresolved tool invocation."

  @enforce_keys [
    :invocation_id,
    :tool_name,
    :status,
    :conversation_mode,
    :source_turn_id
  ]
  defstruct @enforce_keys

  @type status :: :running | :terminal_queued | :completion_admitted
  @type conversation_mode :: :blocking | :non_blocking
  @type t :: %__MODULE__{
          invocation_id: String.t(),
          tool_name: String.t(),
          status: status(),
          conversation_mode: conversation_mode(),
          source_turn_id: String.t()
        }

  @maximum_identifier_bytes 256
  @maximum_tool_name_bytes 128

  @spec new(keyword()) :: {:ok, t()} | {:error, atom()}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <-
           Keyword.validate(attributes, [
             :invocation_id,
             :tool_name,
             :status,
             :conversation_mode,
             :source_turn_id
           ]),
         {:ok, invocation_id} <-
           validate_identifier(Keyword.get(attributes, :invocation_id)),
         {:ok, tool_name} <- validate_tool_name(Keyword.get(attributes, :tool_name)),
         {:ok, status} <- validate_status(Keyword.get(attributes, :status)),
         {:ok, conversation_mode} <-
           validate_conversation_mode(Keyword.get(attributes, :conversation_mode)),
         {:ok, source_turn_id} <-
           validate_identifier(Keyword.get(attributes, :source_turn_id)) do
      {:ok,
       %__MODULE__{
         invocation_id: invocation_id,
         tool_name: tool_name,
         status: status,
         conversation_mode: conversation_mode,
         source_turn_id: source_turn_id
       }}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_pending_invocation}
    end
  end

  def new(_attributes), do: {:error, :invalid_pending_invocation}

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = invocation) do
    match?({:ok, _value}, validate_identifier(invocation.invocation_id)) and
      match?({:ok, _value}, validate_tool_name(invocation.tool_name)) and
      match?({:ok, _value}, validate_status(invocation.status)) and
      match?({:ok, _value}, validate_conversation_mode(invocation.conversation_mode)) and
      match?({:ok, _value}, validate_identifier(invocation.source_turn_id))
  end

  def valid?(_invocation), do: false

  defp validate_identifier(identifier)
       when is_binary(identifier) and byte_size(identifier) > 0 and
              byte_size(identifier) <= @maximum_identifier_bytes,
       do: {:ok, identifier}

  defp validate_identifier(_identifier), do: {:error, :invalid_identifier}

  defp validate_tool_name(name)
       when is_binary(name) and byte_size(name) > 0 and
              byte_size(name) <= @maximum_tool_name_bytes,
       do: {:ok, name}

  defp validate_tool_name(_name), do: {:error, :invalid_tool_name}

  defp validate_status(status)
       when status in [:running, :terminal_queued, :completion_admitted],
       do: {:ok, status}

  defp validate_status(_status), do: {:error, :invalid_status}

  defp validate_conversation_mode(mode) when mode in [:blocking, :non_blocking],
    do: {:ok, mode}

  defp validate_conversation_mode(_mode), do: {:error, :invalid_conversation_mode}
end
