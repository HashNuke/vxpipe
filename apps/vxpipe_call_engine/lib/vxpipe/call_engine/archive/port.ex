defmodule Vxpipe.CallEngine.Archive.Port do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.{EventProjection, Fact, Handoff, Sanitizer}

  @derive {Inspect, except: [:handoff]}
  @enforce_keys [
    :handoff,
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :source_policy,
    :next_sequence
  ]
  defstruct @enforce_keys

  @type identity :: %{
          required(:tenant_id) => String.t(),
          required(:call_id) => String.t(),
          required(:room_id) => String.t(),
          required(:incarnation_id) => String.t()
        }

  @type t :: %__MODULE__{
          handoff: Handoff.t(),
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          source_policy: map(),
          next_sequence: pos_integer()
        }

  @spec new(nil | Handoff.t(), identity(), map()) :: nil | t()
  def new(nil, _identity, _source_policy), do: nil

  def new(%Handoff{} = handoff, identity, source_policy) when is_map(source_policy) do
    %__MODULE__{
      handoff: handoff,
      tenant_id: Map.fetch!(identity, :tenant_id),
      call_id: Map.fetch!(identity, :call_id),
      room_id: Map.fetch!(identity, :room_id),
      incarnation_id: Map.fetch!(identity, :incarnation_id),
      source_policy: Sanitizer.sanitize(source_policy),
      next_sequence: 1
    }
  end

  @spec emit(nil | t(), atom(), keyword()) :: nil | t()
  def emit(nil, _kind, _attributes), do: nil

  def emit(%__MODULE__{} = port, kind, attributes) when is_atom(kind) and is_list(attributes) do
    fact =
      Fact.new!(
        id: Keyword.fetch!(attributes, :id),
        kind: kind,
        sequence: port.next_sequence,
        tenant_id: port.tenant_id,
        call_id: port.call_id,
        room_id: port.room_id,
        incarnation_id: port.incarnation_id,
        participant_id: Keyword.get(attributes, :participant_id),
        activation_id: Keyword.get(attributes, :activation_id),
        source_participant_id: Keyword.get(attributes, :source_participant_id),
        connection_id: Keyword.get(attributes, :connection_id),
        command_id: Keyword.get(attributes, :command_id),
        correlation_id: Keyword.get(attributes, :correlation_id),
        tool_call_id: Keyword.get(attributes, :tool_call_id),
        public_sequence: Keyword.get(attributes, :public_sequence),
        occurred_at: Keyword.fetch!(attributes, :occurred_at),
        source_policy: port.source_policy,
        payload: Keyword.get(attributes, :payload, %{})
      )

    _accepted_or_dropped = Handoff.offer(port.handoff, fact)
    %{port | next_sequence: port.next_sequence + 1}
  end

  @spec emit_event(nil | t(), struct(), keyword()) :: nil | t()
  def emit_event(port, event, additional_attributes \\ []) when is_list(additional_attributes) do
    case EventProjection.project(event) do
      :ignore ->
        port

      {kind, attributes} ->
        projected_payload = Keyword.fetch!(attributes, :payload)
        additional_payload = Keyword.get(additional_attributes, :payload, %{})

        attributes =
          attributes
          |> Keyword.merge(Keyword.delete(additional_attributes, :payload))
          |> Keyword.put(:payload, Map.merge(projected_payload, additional_payload))

        emit(port, kind, attributes)
    end
  end
end
