defmodule Vxpipe.Calls.CallFact do
  @moduledoc "An immutable, private fact observed during one call incarnation."

  alias Vxpipe.Calls.ArchiveSanitizer

  @derive {Inspect, except: [:source_policy, :payload]}
  @kinds [
    :room_opened,
    :participant_joined,
    :participant_left,
    :connection_attached,
    :connection_detached,
    :participant_turn_started,
    :participant_turn_completed,
    :participant_transcription_final,
    :accepted_input,
    :agent_output_generated,
    :agent_output_delivery_started,
    :agent_output_delivery_progressed,
    :agent_output_delivered,
    :agent_turn_completed,
    :agent_turn_failed,
    :agent_turn_interrupted,
    :tool_call_started,
    :tool_call_completed,
    :tool_call_failed,
    :tool_call_cancelled,
    :participant_transfer_started,
    :participant_transfer_completed,
    :participant_transfer_failed,
    :usage_observed,
    :outgoing_dial_submitted,
    :outgoing_call_answered,
    :outgoing_dial_ended,
    :archive_stream_closed
  ]
  @kinds_by_name Map.new(@kinds, fn kind -> {Atom.to_string(kind), kind} end)
  @required_fields [
    :id,
    :kind,
    :sequence,
    :tenant_key,
    :call_id,
    :room_id,
    :incarnation_id,
    :occurred_at,
    :source_policy,
    :payload
  ]
  @optional_fields [
    :participant_id,
    :activation_id,
    :source_participant_id,
    :connection_id,
    :command_id,
    :correlation_id,
    :tool_call_id,
    :public_sequence
  ]
  @identifier_fields [
    :id,
    :tenant_key,
    :call_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :activation_id,
    :source_participant_id,
    :connection_id,
    :command_id,
    :correlation_id,
    :tool_call_id
  ]

  @enforce_keys @required_fields
  defstruct @required_fields ++ @optional_fields

  @type t :: %__MODULE__{
          id: String.t(),
          kind: atom(),
          sequence: pos_integer(),
          tenant_key: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t() | nil,
          activation_id: String.t() | nil,
          source_participant_id: String.t() | nil,
          connection_id: String.t() | nil,
          command_id: String.t() | nil,
          correlation_id: String.t() | nil,
          tool_call_id: String.t() | nil,
          public_sequence: pos_integer() | nil,
          occurred_at: DateTime.t(),
          source_policy: map(),
          payload: map()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_call_fact}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <- Keyword.validate(attributes, @required_fields ++ @optional_fields),
         :ok <- required(attributes),
         :ok <- validate_identity(attributes),
         :ok <- validate_kind_and_sequence(attributes),
         {:ok, attributes} <- canonicalize_json(attributes),
         :ok <-
           Vxpipe.Calls.OutgoingCallFact.validate(
             Keyword.fetch!(attributes, :kind),
             Keyword.fetch!(attributes, :payload)
           ) do
      {:ok, struct!(__MODULE__, attributes)}
    else
      _invalid -> {:error, :invalid_call_fact}
    end
  end

  def new(_attributes), do: {:error, :invalid_call_fact}

  @spec decode_kind(String.t()) :: {:ok, atom()} | :error
  def decode_kind(name) when is_binary(name), do: Map.fetch(@kinds_by_name, name)
  def decode_kind(_name), do: :error

  defp required(attributes) do
    if Enum.all?(@required_fields, &Keyword.has_key?(attributes, &1)),
      do: :ok,
      else: {:error, :missing_field}
  end

  defp validate_identity(attributes) do
    identifiers_valid? =
      Enum.all?(@identifier_fields, fn field ->
        case Keyword.get(attributes, field) do
          value when is_binary(value) -> byte_size(value) > 0 and byte_size(value) <= 256
          nil -> field not in @required_fields
          _invalid -> false
        end
      end)

    if identifiers_valid? and match?(%DateTime{}, Keyword.fetch!(attributes, :occurred_at)) and
         is_map(Keyword.fetch!(attributes, :source_policy)) and
         is_map(Keyword.fetch!(attributes, :payload)) do
      :ok
    else
      {:error, :invalid_identity}
    end
  end

  defp validate_kind_and_sequence(attributes) do
    kind = Keyword.fetch!(attributes, :kind)
    sequence = Keyword.fetch!(attributes, :sequence)
    public_sequence = Keyword.get(attributes, :public_sequence)

    if kind in @kinds and is_integer(sequence) and sequence > 0 and
         (is_nil(public_sequence) or (is_integer(public_sequence) and public_sequence > 0)) do
      :ok
    else
      {:error, :invalid_sequence}
    end
  end

  defp canonicalize_json(attributes) do
    source_policy =
      attributes
      |> Keyword.fetch!(:source_policy)
      |> canonical_json()

    payload =
      attributes
      |> Keyword.fetch!(:payload)
      |> canonical_json()
      |> ArchiveSanitizer.filter_payload(Keyword.fetch!(attributes, :kind), source_policy)

    {:ok,
     attributes
     |> Keyword.put(:source_policy, source_policy)
     |> Keyword.put(:payload, payload)}
  rescue
    _error -> {:error, :not_json_safe}
  end

  defp canonical_json(value) do
    value
    |> JSON.encode!()
    |> JSON.decode!()
    |> ArchiveSanitizer.sanitize()
  end
end
