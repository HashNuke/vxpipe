defmodule Vxpipe.CallEngine.Command.CreateRoom do
  @moduledoc """
  Requests creation of one logical room and its initial incarnation.
  """

  alias Vxpipe.CallEngine.{Error, Id}

  @schema_version 1
  @required_fields [:tenant_id, :actor_id, :deadline]
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/

  @agents [:deterministic_text, :model_inference]

  @enforce_keys [
    :id,
    :tenant_id,
    :actor_id,
    :room_id,
    :agent,
    :agent_participant_id,
    :deadline
  ]
  defstruct [
    :id,
    :tenant_id,
    :actor_id,
    :room_id,
    :agent,
    :agent_participant_id,
    :deadline,
    schema_version: @schema_version
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          schema_version: pos_integer(),
          tenant_id: String.t(),
          actor_id: String.t(),
          room_id: String.t(),
          agent: nil | :deterministic_text | :model_inference,
          agent_participant_id: nil | String.t(),
          deadline: DateTime.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    with :ok <- validate_required(options),
         {:ok, tenant_id} <- validate_identifier(:tenant_id, Keyword.fetch!(options, :tenant_id)),
         {:ok, actor_id} <- validate_identifier(:actor_id, Keyword.fetch!(options, :actor_id)),
         {:ok, command_id} <-
           validate_identifier(:id, Keyword.get(options, :id, Id.generate(:command))),
         {:ok, room_id} <-
           validate_identifier(:room_id, Keyword.get(options, :room_id, Id.generate(:room))),
         {:ok, agent} <- validate_agent(Keyword.get(options, :agent)),
         {:ok, agent_participant_id} <-
           validate_agent_participant_id(agent, Keyword.get(options, :agent_participant_id)),
         {:ok, deadline} <- validate_deadline(Keyword.fetch!(options, :deadline)) do
      {:ok,
       %__MODULE__{
         id: command_id,
         tenant_id: tenant_id,
         actor_id: actor_id,
         room_id: room_id,
         agent: agent,
         agent_participant_id: agent_participant_id,
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

  defp validate_agent(nil), do: {:ok, nil}
  defp validate_agent(agent) when agent in @agents, do: {:ok, agent}
  defp validate_agent(_agent), do: invalid(:agent, "must be a supported agent kind")

  defp validate_agent_participant_id(nil, nil), do: {:ok, nil}

  defp validate_agent_participant_id(nil, _participant_id) do
    invalid(:agent_participant_id, "requires an agent")
  end

  defp validate_agent_participant_id(_agent, nil) do
    {:ok, Id.generate(:participant)}
  end

  defp validate_agent_participant_id(_agent, participant_id) do
    validate_identifier(:agent_participant_id, participant_id)
  end

  defp validate_deadline(%DateTime{} = deadline), do: {:ok, deadline}
  defp validate_deadline(_value), do: invalid(:deadline, "must be a DateTime")

  defp invalid(field, reason) do
    {:error,
     Error.new(
       :invalid_command,
       "The create-room command is invalid.",
       details: %{"field" => Atom.to_string(field), "reason" => reason}
     )}
  end
end
