defmodule Vxpipe.CallEngine.RoomAuthority.DiagnosticInputs do
  @moduledoc "Bounded accepted human STT bindings, independent of response-agent capabilities."
  alias Vxpipe.CallEngine.RoomAuthority.State

  @doc "Room-service bounded snapshot; never waits on a speech provider or model."
  def query(room_authority, cursor \\ nil, limit \\ 16) do
    GenServer.call(room_authority, {:diagnostic_inputs, cursor, limit}, 250)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @doc "Exact connection lookup for revalidation, independent of page insertion or removal."
  def for_connection(room_authority, connection_id),
    do: query(room_authority, {:connection, connection_id}, 1)

  def read(%State{} = state, {:connection, connection_id}, 1) do
    if identifier?(connection_id),
      do:
        candidates(%{state | connections: Map.take(state.connections, [connection_id])}, nil, 1),
      else: {:error, :invalid_query}
  end

  def read(%State{} = state, cursor, limit) do
    if (is_nil(cursor) or identifier?(cursor)) and is_integer(limit) and limit in 1..32,
      do: candidates(state, cursor, limit),
      else: {:error, :invalid_query}
  end

  defp candidates(%{participant_transfer_runtime: %{plan: plan}} = state, cursor, limit) do
    identity = %{
      tenant_id: plan.tenant_id,
      call_id: plan.call_id,
      room_id: plan.room_id,
      incarnation_id: state.snapshot.incarnation_id
    }

    eligible? =
      state.snapshot.lifecycle == :open and state.startup_ready? and
        not match?(%{status: :pending}, state.outgoing_admission) and
        plan.tenant_id == state.snapshot.tenant_id and plan.room_id == state.snapshot.room_id and
        Enum.all?(Map.values(identity), &identifier?/1)

    if eligible? do
      human_ids =
        plan.participants
        |> Map.values()
        |> Enum.filter(&(&1.kind == :human))
        |> Enum.map(& &1.participant_id)
        |> MapSet.new()

      candidates =
        state.connections
        |> Enum.sort_by(&elem(&1, 0))
        |> Stream.filter(fn {id, connection} ->
          identifier?(id) and (cursor == nil or id > cursor) and
            current_source?(connection, state, human_ids)
        end)
        |> Enum.take(limit + 1)

      sources =
        candidates
        |> Enum.take(limit)
        |> Enum.map(fn {id, connection} ->
          %{
            connection_id: :binary.copy(id),
            participant_id: :binary.copy(connection.participant_id),
            capability: connection.speech_to_text.capability
          }
        end)

      {:ok,
       %{
         identity: Map.new(identity, fn {key, value} -> {key, :binary.copy(value)} end),
         sources: sources,
         next_cursor: if(length(candidates) > limit, do: List.last(sources).connection_id)
       }}
    else
      {:error, :unavailable}
    end
  end

  defp candidates(_state, _cursor, _limit), do: {:error, :unavailable}

  # Dispatch holds (including agent preparation) do not revoke an accepted STT binding.
  # These are candidates only; attachment and capture still enforce input-policy intervals.
  defp current_source?(
         %{
           role: :human,
           admission: :main,
           participant_id: participant,
           speech_to_text: %{capability: capability}
         },
         state,
         human_ids
       ) do
    is_pid(capability) and node(capability) == node() and identifier?(participant) and
      MapSet.member?(human_ids, participant) and
      MapSet.member?(state.participant_ids, participant)
  end

  defp current_source?(_connection, _state, _human_ids), do: false
  defp identifier?(value), do: is_binary(value) and byte_size(value) in 1..256
end
