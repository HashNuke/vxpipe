defmodule Vxpipe.Console.Test.SavedMCPRepository do
  @moduledoc false

  alias Vxpipe.Persistence.MCP.ConnectionStore

  def list(state, tenant), do: call(state, :list, [tenant])
  def resolve(state, tenant, id), do: call(state, :resolve, [tenant, id])

  def available(state, value), do: Agent.update(state, &%{&1 | available: value})

  def operations(state),
    do: Agent.get_and_update(state, &{Enum.reverse(&1.operations), %{&1 | operations: []}})

  defp call(state, operation, arguments) do
    {available, context} =
      Agent.get_and_update(state, fn current ->
        {{current.available, current.context},
         %{current | operations: [{operation, arguments} | current.operations]}}
      end)

    if available,
      do: apply(ConnectionStore, operation, [context | arguments]),
      else: {:error, :mcp_connections_unavailable}
  end
end
