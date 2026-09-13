defmodule Vxpipe.CallEngine.Readiness.Preparation do
  @moduledoc "Expands authoritative room requirements into exact resources for readiness collection."

  alias Vxpipe.CallEngine.Media.ConnectionReadiness
  alias Vxpipe.CallEngine.Readiness.{RecordingPreparation, Resource, ResourceQuery, RoomInventory}

  @task_supervisor Vxpipe.CallEngine.ReadinessTaskSupervisor
  @maximum_resources 256
  @enforce_keys [:inventory, :connections, :recording_tracks, :resources]
  defstruct @enforce_keys

  def run(room, candidate, timeout \\ 5_000) when is_integer(timeout) and timeout > 0 do
    deadline = System.monotonic_time(:millisecond) + timeout

    results =
      Task.Supervisor.async_stream_nolink(
        @task_supervisor,
        [room],
        &safe_prepare(&1, candidate, deadline),
        max_concurrency: 1,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    case results do
      [{:ok, result}] -> result
      _expired -> {:error, :deadline_elapsed}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp safe_prepare(room, candidate, deadline) do
    with {:ok, captured} <- RoomInventory.capture(room, candidate, remaining(deadline)),
         deadline = attempt_deadline(captured, deadline),
         :ok <- connected(captured),
         {:ok, collected} <- collect(captured, deadline),
         {resources, connections} = unpack(collected),
         {:ok, tracks, recording} <- RecordingPreparation.prepare(captured, connections),
         {:ok, resources} <- complete_resources(resources ++ recording, captured),
         :ok <- RoomInventory.validate(room, captured, remaining(deadline)) do
      _remaining = remaining(deadline)

      {:ok,
       %__MODULE__{
         inventory: captured,
         connections: connections,
         recording_tracks: tracks,
         resources: resources
       }}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, :readiness_preparation_timeout -> {:error, :deadline_elapsed}
    _kind, _reason -> {:error, :unavailable}
  end

  defp collect(captured, deadline) do
    requests(captured)
    |> Task.async_stream(&observe(&1, captured, deadline),
      max_concurrency: 8,
      timeout: remaining(deadline),
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, result}}, {:ok, results} -> {:cont, {:ok, [result | results]}}
      {:ok, {:error, _reason} = failure}, _results -> {:halt, failure}
      _unavailable, _results -> {:halt, {:error, :unavailable}}
    end)
  end

  defp requests(captured) do
    room =
      for {kind, instance} <- captured.room,
          kind != :recording,
          do: {:resource, kind, :room, instance}

    participants =
      for {id, capabilities} <- captured.participants,
          {kind, instance} <- capabilities,
          do: {:resource, kind, {:participant, id}, instance}

    connections =
      for {id, request} <- captured.inventory.connections,
          do: {:connection, id, request}

    Enum.sort(room ++ participants ++ connections)
  end

  defp observe({:resource, kind, scope, instance}, captured, _deadline),
    do: ResourceQuery.observe(kind, scope, instance, captured.candidate.snapshot)

  defp observe({:connection, id, request}, captured, deadline) do
    identity =
      captured.identity
      |> Map.take([:tenant_id, :room_id, :incarnation_id])
      |> Map.merge(%{participant_id: request.participant_id, connection_id: id})

    case ConnectionReadiness.prepare_graph(
           request.instance,
           identity,
           captured.candidate.snapshot,
           request.demand,
           remaining(deadline)
         ) do
      {:ok, graph} ->
        {:ok, {id, graph}}

      {:error, reason} ->
        ResourceQuery.failure(
          :media_connection,
          {:participant, request.participant_id},
          safe_reason(reason)
        )
    end
  end

  defp unpack(results) do
    Enum.reduce(results, {[], %{}}, fn
      %Resource{} = resource, {resources, connections} ->
        {[resource | resources], connections}

      {id, graph}, {resources, connections} ->
        {graph.resources ++ resources, Map.put(connections, id, graph)}
    end)
  end

  defp complete_resources(resources, captured) do
    if Enum.all?(resources, &valid_resource?(&1, captured.inventory.participant_ids)),
      do: unique_resources(resources),
      else: {:error, :invalid_resources}
  end

  defp valid_resource?(%Resource{} = resource, participants) do
    permitted_scope? =
      case resource.scope do
        :room -> true
        {:participant, id} -> MapSet.member?(participants, id)
        _foreign -> false
      end

    Resource.bound?(resource) and is_binary(resource.configuration) and permitted_scope?
  end

  defp valid_resource?(_resource, _participants), do: false

  defp unique_resources(resources) do
    grouped = Enum.group_by(resources, &Resource.key/1)

    cond do
      map_size(grouped) > @maximum_resources ->
        {:error, :too_many_readiness_resources}

      Enum.any?(grouped, fn {_key, entries} -> length(Enum.uniq(entries)) != 1 end) ->
        {:error, :conflicting_resources}

      true ->
        {:ok, grouped |> Enum.sort() |> Enum.map(fn {_key, [resource | _]} -> resource end)}
    end
  end

  defp connected(captured) do
    case Enum.sort(captured.inventory.missing_participants) do
      [] -> :ok
      [id | _missing] -> ResourceQuery.failure(:media_connection, {:participant, id}, :missing)
    end
  end

  defp attempt_deadline(%{binding: %{attempt: nil}}, deadline), do: deadline

  defp attempt_deadline(captured, deadline),
    do: min(captured.binding.attempt.deadline_ms, deadline)

  defp safe_reason(reason) when is_atom(reason), do: reason
  defp safe_reason(_reason), do: :unavailable

  defp remaining(deadline) do
    case deadline - System.monotonic_time(:millisecond) do
      remaining when remaining > 0 -> remaining
      _expired -> exit(:readiness_preparation_timeout)
    end
  end
end
