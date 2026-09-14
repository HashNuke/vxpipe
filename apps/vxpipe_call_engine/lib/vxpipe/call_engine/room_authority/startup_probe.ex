defmodule Vxpipe.CallEngine.RoomAuthority.StartupProbe do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.ConnectionReadiness
  alias Vxpipe.CallEngine.MediaPolicy.Authority
  alias Vxpipe.CallEngine.Readiness.{Preparation, RoomInventory}
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

      with {:ok, candidate} <-
             Authority.preview_presence(policy_authority, policy.present_participant_ids),
           {:ok, graph} <- Preparation.run(room, candidate, remaining(deadline)),
           :ok <- collect(graph.resources, incarnation, deadline),
           :ok <- RoomInventory.validate(room, graph.inventory, remaining(deadline)) do
        :ok
      end
    end)
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
        await(collector, deadline)
      after
        RoomCapabilitySupervisor.stop_capability(incarnation, collector)
      end
    end
  end

  defp await(collector, deadline) do
    receive do
      {:vxpipe_readiness_changed, ^collector, %{status: :ready}} ->
        :ok

      {:vxpipe_readiness_changed, ^collector, %{status: :failed, failure: :binding_changed}} ->
        {:error, :binding_changed}

      {:vxpipe_readiness_changed, ^collector, %{status: :failed}} ->
        {:error, :readiness_failed}

      {:vxpipe_readiness_changed, ^collector, _preparing} ->
        await(collector, deadline)
    after
      remaining(deadline) -> {:error, :deadline_elapsed}
    end
  end

  defp retry(deadline, operation) do
    case safe_run(operation) do
      :ok ->
        :ok

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
