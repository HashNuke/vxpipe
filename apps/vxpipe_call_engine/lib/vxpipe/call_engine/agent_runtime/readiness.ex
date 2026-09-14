defmodule Vxpipe.CallEngine.AgentRuntime.Readiness do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Session
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.State
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.Tool.InvocationRegistry

  # Dependency queries run in the collector's caller, never inside the coordinator.
  def readiness(coordinator) do
    with {:ok, resource, own_status, dependencies} <-
           GenServer.call(coordinator, :readiness_binding, 1_000),
         {:ok, session, session_status} <- Session.readiness(dependencies.session),
         {:ok, tools, tools_status} <- InvocationRegistry.readiness(dependencies.tools),
         {:ok, remote, remote_status} <- remote_readiness(dependencies.remote),
         {:ok, request_supervisor} <- supervisor_readiness(dependencies.requests) do
      resource = %{
        resource
        | configuration:
            Resource.signature(
              {resource.configuration, session, tools, remote, request_supervisor}
            )
      }

      {:ok, resource, status([own_status, session_status, tools_status, remote_status])}
    else
      _unavailable -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def binding(%State{} = state) do
    dependencies = %{
      session: state.session,
      tools: state.invocation_registry,
      remote: state.remote_mcp_owner,
      requests: state.request_supervisor
    }

    {:ok, state.readiness_resource, :ready, dependencies}
  end

  defp supervisor_readiness(server) do
    with pid when is_pid(pid) <- GenServer.whereis(server),
         %{active: _active} <- DynamicSupervisor.count_children(pid) do
      {:ok, pid}
    end
  end

  defp remote_readiness(nil), do: {:ok, nil, :ready}
  defp remote_readiness(owner), do: IntegrationOwner.readiness(owner)

  defp status(statuses) do
    cond do
      :failed in statuses -> :failed
      :preparing in statuses -> :preparing
      true -> :ready
    end
  end
end
