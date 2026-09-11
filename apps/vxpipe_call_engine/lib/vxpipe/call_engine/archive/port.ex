defmodule Vxpipe.CallEngine.Archive.Port do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.{EventProjection, Fact, Handoff, Policy, Sanitizer}
  alias Vxpipe.CallEngine.LiveInspection.Port, as: LiveInspectionPort

  @derive {Inspect, except: [:handoff, :live_inspection_port]}
  @enforce_keys [
    :handoff,
    :live_inspection_port,
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
          handoff: nil | Handoff.t(),
          live_inspection_port: nil | LiveInspectionPort.t(),
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          source_policy: map(),
          next_sequence: pos_integer()
        }

  @spec new(nil | Handoff.t(), identity(), map()) :: nil | t()
  def new(handoff, identity, source_policy), do: new(handoff, nil, identity, source_policy)

  @spec new(nil | Handoff.t(), nil | LiveInspectionPort.t(), identity(), map()) :: nil | t()
  def new(nil, nil, _identity, _source_policy), do: nil

  def new(handoff, live_inspection_port, identity, source_policy)
      when (is_nil(handoff) or is_struct(handoff, Handoff)) and
             (is_nil(live_inspection_port) or is_struct(live_inspection_port, LiveInspectionPort)) and
             is_map(source_policy) do
    %__MODULE__{
      handoff: handoff,
      live_inspection_port: live_inspection_port,
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
    source_policy =
      Map.merge(port.source_policy, Keyword.get(attributes, :source_policy, %{}))

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
        source_policy: source_policy,
        payload:
          Policy.filter_payload(
            kind,
            Keyword.get(attributes, :payload, %{}),
            source_policy
          )
      )

    offer_archive(port.handoff, fact)
    offer_live_inspection(port.live_inspection_port, fact)
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

  defp offer_archive(nil, _fact), do: :ok

  defp offer_archive(handoff, fact) do
    _accepted_or_dropped = Handoff.offer(handoff, fact)
    :ok
  end

  defp offer_live_inspection(nil, _fact), do: :ok

  defp offer_live_inspection(live_inspection_port, fact) do
    _accepted_or_dropped = LiveInspectionPort.offer(live_inspection_port, fact)
    :ok
  end
end
