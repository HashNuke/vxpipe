defmodule Vxpipe.CallEngine.Command.UpdateCallVariables do
  @moduledoc """
  Applies one optimistic Call Variables update using trusted attribution.
  """

  alias Vxpipe.CallEngine.{Error, Id}

  @schema_version 1
  @required_fields [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :activation_id,
    :source_participant_id,
    :correlation_id,
    :tool_call_id,
    :section,
    :expected_revision,
    :operation,
    :deadline
  ]
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/

  @enforce_keys [
    :id,
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :activation_id,
    :source_participant_id,
    :correlation_id,
    :tool_call_id,
    :section,
    :expected_revision,
    :operation,
    :deadline
  ]
  defstruct @enforce_keys ++ [schema_version: @schema_version]

  @type operation :: {:merge, map()} | {:put, String.t(), term()}
  @type t :: %__MODULE__{
          id: String.t(),
          schema_version: pos_integer(),
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          activation_id: String.t(),
          source_participant_id: String.t(),
          correlation_id: String.t(),
          tool_call_id: String.t(),
          section: String.t(),
          expected_revision: non_neg_integer(),
          operation: operation(),
          deadline: DateTime.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    with :ok <- validate_required(options),
         {:ok, id} <- validate_identifier(:id, Keyword.get(options, :id, Id.generate(:command))),
         {:ok, tenant_id} <- validate_identifier(:tenant_id, Keyword.fetch!(options, :tenant_id)),
         {:ok, room_id} <- validate_identifier(:room_id, Keyword.fetch!(options, :room_id)),
         {:ok, incarnation_id} <-
           validate_identifier(:incarnation_id, Keyword.fetch!(options, :incarnation_id)),
         {:ok, participant_id} <-
           validate_identifier(:participant_id, Keyword.fetch!(options, :participant_id)),
         {:ok, activation_id} <-
           validate_identifier(:activation_id, Keyword.fetch!(options, :activation_id)),
         {:ok, source_participant_id} <-
           validate_identifier(
             :source_participant_id,
             Keyword.fetch!(options, :source_participant_id)
           ),
         {:ok, correlation_id} <-
           validate_identifier(:correlation_id, Keyword.fetch!(options, :correlation_id)),
         {:ok, tool_call_id} <-
           validate_identifier(:tool_call_id, Keyword.fetch!(options, :tool_call_id)),
         {:ok, section} <- validate_identifier(:section, Keyword.fetch!(options, :section)),
         {:ok, expected_revision} <-
           validate_revision(Keyword.fetch!(options, :expected_revision)),
         {:ok, operation} <- validate_operation(Keyword.fetch!(options, :operation)),
         {:ok, deadline} <- validate_deadline(Keyword.fetch!(options, :deadline)) do
      {:ok,
       %__MODULE__{
         id: id,
         tenant_id: tenant_id,
         room_id: room_id,
         incarnation_id: incarnation_id,
         participant_id: participant_id,
         activation_id: activation_id,
         source_participant_id: source_participant_id,
         correlation_id: correlation_id,
         tool_call_id: tool_call_id,
         section: section,
         expected_revision: expected_revision,
         operation: operation,
         deadline: deadline
       }}
    end
  end

  defp validate_required(options) do
    case Enum.find(@required_fields, &(not Keyword.has_key?(options, &1))) do
      nil -> :ok
      field -> invalid(field, "is required")
    end
  end

  defp validate_identifier(field, value) when is_binary(value) do
    if Regex.match?(@identifier_pattern, value) do
      {:ok, value}
    else
      invalid(field, "must contain 1-128 URL-safe identifier characters")
    end
  end

  defp validate_identifier(field, _value), do: invalid(field, "must be a string")

  defp validate_revision(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp validate_revision(_value), do: invalid(:expected_revision, "must be non-negative")

  defp validate_operation({:merge, data}) when is_map(data), do: {:ok, {:merge, data}}

  defp validate_operation({:put, variable, value}) when is_binary(variable) do
    {:ok, {:put, variable, value}}
  end

  defp validate_operation(_operation) do
    invalid(:operation, "must be a section merge or literal variable update")
  end

  defp validate_deadline(%DateTime{} = deadline), do: {:ok, deadline}
  defp validate_deadline(_value), do: invalid(:deadline, "must be a DateTime")

  defp invalid(field, reason) do
    {:error,
     Error.new(:invalid_command, "The update-call-variables command is invalid.",
       details: %{"field" => Atom.to_string(field), "reason" => reason}
     )}
  end
end
