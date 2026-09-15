defmodule Vxpipe.CallEngine.Command.JoinParticipant do
  @moduledoc """
  Requests admission of one participant to an existing room incarnation.
  """

  alias Vxpipe.CallEngine.{Error, Id}

  @schema_version 1
  @required_fields [:tenant_id, :actor_id, :room_id, :role, :deadline]
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/
  @roles [:agent, :human, :monitor]

  @enforce_keys [:id, :tenant_id, :actor_id, :room_id, :participant_id, :role, :deadline]
  defstruct [
    :id,
    :tenant_id,
    :actor_id,
    :room_id,
    :participant_id,
    :role,
    :deadline,
    schema_version: @schema_version
  ]

  @type role :: :agent | :human | :monitor

  @type t :: %__MODULE__{
          id: String.t(),
          schema_version: pos_integer(),
          tenant_id: String.t(),
          actor_id: String.t(),
          room_id: String.t(),
          participant_id: String.t(),
          role: role(),
          deadline: DateTime.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    with :ok <- validate_required(options),
         {:ok, tenant_id} <- validate_identifier(:tenant_id, Keyword.fetch!(options, :tenant_id)),
         {:ok, actor_id} <- validate_identifier(:actor_id, Keyword.fetch!(options, :actor_id)),
         {:ok, room_id} <- validate_identifier(:room_id, Keyword.fetch!(options, :room_id)),
         {:ok, command_id} <-
           validate_identifier(:id, Keyword.get(options, :id, Id.generate(:command))),
         {:ok, participant_id} <-
           validate_identifier(
             :participant_id,
             Keyword.get(options, :participant_id, Id.generate(:participant))
           ),
         {:ok, role} <- validate_role(Keyword.fetch!(options, :role)),
         {:ok, deadline} <- validate_deadline(Keyword.fetch!(options, :deadline)) do
      {:ok,
       %__MODULE__{
         id: command_id,
         tenant_id: tenant_id,
         actor_id: actor_id,
         room_id: room_id,
         participant_id: participant_id,
         role: role,
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
    pattern =
      if field == :tenant_id, do: ~r/\A[A-Za-z0-9_-]{1,128}\z/, else: @identifier_pattern

    if Regex.match?(pattern, value) do
      {:ok, value}
    else
      invalid(field, "must contain 1-128 URL-safe identifier characters")
    end
  end

  defp validate_identifier(field, _value), do: invalid(field, "must be a string")

  defp validate_role(role) when role in @roles, do: {:ok, role}
  defp validate_role(_role), do: invalid(:role, "must be a supported participant role")

  defp validate_deadline(%DateTime{} = deadline), do: {:ok, deadline}
  defp validate_deadline(_value), do: invalid(:deadline, "must be a DateTime")

  defp invalid(field, reason) do
    {:error,
     Error.new(
       :invalid_command,
       "The join-participant command is invalid.",
       details: %{"field" => Atom.to_string(field), "reason" => reason}
     )}
  end
end
