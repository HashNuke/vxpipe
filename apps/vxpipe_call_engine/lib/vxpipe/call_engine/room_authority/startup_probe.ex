defmodule Vxpipe.CallEngine.RoomAuthority.StartupProbe do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.ConnectionReadiness
  alias Vxpipe.CallEngine.MediaPolicy.Authority
  alias Vxpipe.CallEngine.Readiness.{Preparation, Probe, RoomInventory}
  alias Vxpipe.CallEngine.RoomCapabilitySupervisor

  def output(connection, identity, policy_authority, deadline) do
    retry(deadline, fn ->
      policy = Authority.snapshot(policy_authority)

      with {:ok, graph} <-
             ConnectionReadiness.prepare_graph(
               connection,
               identity,
               policy,
               [],
               remaining(deadline)
             ),
           :ok <- collect(graph.resources, identity.incarnation_id, deadline) do
        :ok
      end
    end)
  end

  def room(room, policy_authority, incarnation, deadline) do
    retry(deadline, fn ->
      policy = Authority.snapshot(policy_authority)

      result =
        with {:ok, candidate} <-
               Authority.preview_presence(policy_authority, policy.present_participant_ids),
             {:ok, graph} <- Preparation.run(room, candidate, remaining(deadline)),
             :ok <- collect(graph.resources, incarnation, deadline),
             :ok <- RoomInventory.validate(room, graph.inventory, remaining(deadline)) do
          {:ok, graph}
        end

      case result do
        {:error, %{kind: kind}} ->
          _ = Vxpipe.CallEngine.CallLifecycle.startup_progress(incarnation, self(), [kind])
          result

        _other ->
          result
      end
    end)
  end

  def verify(room, graph, deadline) do
    incarnation = graph.inventory.identity.incarnation_id

    report = fn blockers ->
      Vxpipe.CallEngine.CallLifecycle.startup_progress(incarnation, :release, blockers)
    end

    result =
      safe_run(fn ->
        with :ok <- RoomInventory.validate(room, graph.inventory, remaining(deadline)),
             :ok <- Probe.verify(graph.resources, min(100, remaining(deadline)), report),
             :ok <- RoomInventory.validate(room, graph.inventory, remaining(deadline)) do
          :ok
        end
      end)

    if remaining(deadline) > 0, do: result, else: {:error, :deadline_elapsed}
  end

  defp collect(resources, incarnation, deadline) do
    with {:ok, collector} <-
           RoomCapabilitySupervisor.start_readiness(incarnation,
             owner: self(),
             attempt_id: "call-setup",
             deadline_ms: deadline,
             resources: resources
           ) do
      try do
        await(collector, incarnation, deadline)
      after
        RoomCapabilitySupervisor.stop_capability(incarnation, collector)
      end
    end
  end

  defp await(collector, incarnation, deadline) do
    receive do
      {:vxpipe_readiness_changed, ^collector, report} ->
        _ = Vxpipe.CallEngine.CallLifecycle.startup_progress(incarnation, self(), report.blockers)

        case report do
          %{status: :ready} -> :ok
          %{status: :failed, failure: :binding_changed} -> {:error, :binding_changed}
          %{status: :failed} -> {:error, :readiness_failed}
          _preparing -> await(collector, incarnation, deadline)
        end
    after
      remaining(deadline) -> {:error, :deadline_elapsed}
    end
  end

  defp retry(deadline, operation) do
    case safe_run(operation) do
      :ok ->
        :ok

      {:ok, _graph} = ready ->
        ready

      {:error, reason} when reason in [:readiness_failed, :deadline_elapsed] ->
        {:error, reason}

      _preparing ->
        if remaining(deadline) > 0 do
          receive do
          after
            min(100, remaining(deadline)) -> retry(deadline, operation)
          end
        else
          {:error, :deadline_elapsed}
        end
    end
  end

  defp safe_run(operation) do
    operation.()
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
