defmodule Vxpipe.Gateway.Media.EgressAcceptance do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.EgressAcceptedFrame
  alias Vxpipe.CallEngine.Recording.EgressHandoff

  @spec record(nil | EgressHandoff.t(), map(), String.t(), binary()) :: :ok
  def record(nil, _current, _connection_id, _payload), do: :ok

  def record(%EgressHandoff{} = handoff, current, connection_id, payload)
      when is_map(current) and is_binary(connection_id) and is_binary(payload) do
    frame = %EgressAcceptedFrame{
      tenant_id: current.tenant_id,
      room_id: current.room_id,
      incarnation_id: current.incarnation_id,
      source_participant_id: current.source_participant_id,
      connection_id: connection_id,
      sample_rate: 48_000,
      channels: 1,
      payload: payload
    }

    _outcome = EgressHandoff.offer(handoff, frame)
    :ok
  end
end
