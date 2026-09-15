defmodule Vxpipe.CallEngine.Command.SendText do
  @moduledoc """
  Submits one text turn from an attached participant.
  """

  alias Vxpipe.CallEngine.{Error, Id}

  @schema_version 1
  @max_content_bytes 4_096
  @required_fields [
    :tenant_id,
    :actor_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :connection_id,
    :correlation_id,
    :content,
    :deadline
  ]
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/

  @enforce_keys [
    :id,
    :tenant_id,
    :actor_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :connection_id,
    :correlation_id,
    :content,
    :run_immediately,
    :audio_response,
    :deadline
  ]
  defstruct @enforce_keys ++ [schema_version: @schema_version]

  @type t :: %__MODULE__{
          id: String.t(),
          schema_version: pos_integer(),
          tenant_id: String.t(),
          actor_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          connection_id: String.t(),
          correlation_id: String.t(),
          content: String.t(),
          run_immediately: boolean(),
          audio_response: boolean(),
          deadline: DateTime.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) when is_list(options) do
    with :ok <- validate_required(options),
         {:ok, id} <- validate_identifier(:id, Keyword.get(options, :id, Id.generate(:command))),
         {:ok, tenant_id} <- validate_identifier(:tenant_id, Keyword.fetch!(options, :tenant_id)),
         {:ok, actor_id} <- validate_identifier(:actor_id, Keyword.fetch!(options, :actor_id)),
         {:ok, room_id} <- validate_identifier(:room_id, Keyword.fetch!(options, :room_id)),
         {:ok, incarnation_id} <-
           validate_identifier(:incarnation_id, Keyword.fetch!(options, :incarnation_id)),
         {:ok, participant_id} <-
           validate_identifier(:participant_id, Keyword.fetch!(options, :participant_id)),
         {:ok, connection_id} <-
           validate_identifier(:connection_id, Keyword.fetch!(options, :connection_id)),
         {:ok, correlation_id} <-
           validate_identifier(:correlation_id, Keyword.fetch!(options, :correlation_id)),
         {:ok, content} <- validate_content(Keyword.fetch!(options, :content)),
         {:ok, run_immediately} <-
           validate_boolean(:run_immediately, Keyword.get(options, :run_immediately, true)),
         {:ok, audio_response} <-
           validate_boolean(:audio_response, Keyword.get(options, :audio_response, true)),
         {:ok, deadline} <- validate_deadline(Keyword.fetch!(options, :deadline)) do
      {:ok,
       %__MODULE__{
         id: id,
         tenant_id: tenant_id,
         actor_id: actor_id,
         room_id: room_id,
         incarnation_id: incarnation_id,
         participant_id: participant_id,
         connection_id: connection_id,
         correlation_id: correlation_id,
         content: content,
         run_immediately: run_immediately,
         audio_response: audio_response,
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

  defp validate_content(content) when is_binary(content) do
    if String.valid?(content) and String.trim(content) != "" and
         byte_size(content) <= @max_content_bytes do
      {:ok, content}
    else
      invalid(:content, "must contain 1-4096 bytes of non-whitespace UTF-8 text")
    end
  end

  defp validate_content(_content), do: invalid(:content, "must be a string")

  defp validate_boolean(_field, value) when is_boolean(value), do: {:ok, value}
  defp validate_boolean(field, _value), do: invalid(field, "must be a boolean")

  defp validate_deadline(%DateTime{} = deadline), do: {:ok, deadline}
  defp validate_deadline(_value), do: invalid(:deadline, "must be a DateTime")

  defp invalid(field, reason) do
    {:error,
     Error.new(
       :invalid_command,
       "The send-text command is invalid.",
       details: %{"field" => Atom.to_string(field), "reason" => reason}
     )}
  end
end
