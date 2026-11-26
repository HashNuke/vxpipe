defmodule Vxpipe.Gateway.Media.EgressAcceptance do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.EgressAcceptedFrame
  alias Vxpipe.CallEngine.Recording.EgressHandoff

  @spec record(nil | EgressHandoff.t(), map(), String.t(), binary()) :: :ok
  def record(nil, _current, _connection_id, _payload), do: :ok

  def record(_handoff, %{audio_scope: :mixed}, _connection_id, _payload), do: :ok

  def record(
        %EgressHandoff{} = handoff,
        %{audio_scope: :private} = current,
        connection_id,
        payload
      )
      when is_map(current) and is_binary(connection_id) and is_binary(payload) do
    # Participant-origin private audio (for example an agent transfer briefing
    # to one destination) is never recorded. Room-origin private assets
    # (opening audio, wait sounds, transfer and readiness cues) are offered to
    # the handoff; its timely policy gate decides from the installed snapshot
    # whether this interval is permitted.
    if Map.get(current, :origin, :participant) == :room do
      offer(handoff, current, connection_id, payload, :room)
    else
      :ok
    end
  end

  def record(_handoff, %{audio_scope: :private}, _connection_id, _payload), do: :ok

  def record(%EgressHandoff{} = handoff, current, connection_id, payload)
      when is_map(current) and is_binary(connection_id) and is_binary(payload) do
    offer(handoff, current, connection_id, payload, Map.get(current, :origin, :participant))
  end

  defp offer(handoff, current, connection_id, payload, origin) do
    frame = %EgressAcceptedFrame{
      tenant_id: current.tenant_id,
      room_id: current.room_id,
      incarnation_id: current.incarnation_id,
      source_participant_id: current.source_participant_id,
      connection_id: connection_id,
      sample_rate: 48_000,
      channels: 1,
      origin: origin,
      payload: payload
    }

    _outcome = EgressHandoff.offer(handoff, frame)
    :ok
  end
end
