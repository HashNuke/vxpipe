defmodule Vxpipe.CallEngine.Command.ReadCallVariables do
  @moduledoc """
  Reads selected Call Variables sections using a trusted room identity.
  """

  alias Vxpipe.CallEngine.{Error, Id}

  @schema_version 1
  @max_sections 32
  @required_fields [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :sections,
    :deadline
  ]
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/

  @enforce_keys [
    :id,
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :sections,
    :deadline
  ]
  defstruct @enforce_keys ++ [schema_version: @schema_version]

  @type t :: %__MODULE__{
          id: String.t(),
          schema_version: pos_integer(),
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          sections: [String.t()],
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
         {:ok, sections} <- validate_sections(Keyword.fetch!(options, :sections)),
         {:ok, deadline} <- validate_deadline(Keyword.fetch!(options, :deadline)) do
      {:ok,
       %__MODULE__{
         id: id,
         tenant_id: tenant_id,
         room_id: room_id,
         incarnation_id: incarnation_id,
         participant_id: participant_id,
         sections: sections,
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

  defp validate_sections(sections)
       when is_list(sections) and sections != [] and length(sections) <= @max_sections do
    cond do
      Enum.any?(sections, &(not valid_identifier?(&1))) ->
        invalid(:sections, "must contain only section identifiers")

      length(Enum.uniq(sections)) != length(sections) ->
        invalid(:sections, "must not contain duplicates")

      true ->
        {:ok, sections}
    end
  end

  defp validate_sections(_sections) do
    invalid(:sections, "must contain 1-#{@max_sections} unique section identifiers")
  end

  defp validate_identifier(field, value) when is_binary(value) do
    if valid_identifier?(value) do
      {:ok, value}
    else
      invalid(field, "must contain 1-128 URL-safe identifier characters")
    end
  end

  defp validate_identifier(field, _value), do: invalid(field, "must be a string")

  defp valid_identifier?(value) when is_binary(value),
    do: Regex.match?(@identifier_pattern, value)

  defp valid_identifier?(_value), do: false

  defp validate_deadline(%DateTime{} = deadline), do: {:ok, deadline}
  defp validate_deadline(_value), do: invalid(:deadline, "must be a DateTime")

  defp invalid(field, reason) do
    {:error,
     Error.new(:invalid_command, "The read-call-variables command is invalid.",
       details: %{"field" => Atom.to_string(field), "reason" => reason}
     )}
  end
end
