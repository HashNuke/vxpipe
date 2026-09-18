defmodule Vxpipe.Calls.TestDemoTenantRepository do
  use Agent

  def start_link(_options), do: Agent.start_link(fn -> %{tenant: nil, candidates: []} end)

  def repository(agent), do: {__MODULE__, agent}

  def ensure(agent, candidate) do
    Agent.get_and_update(agent, fn
      %{tenant: nil, candidates: candidates} = state ->
        {{:ok, candidate}, %{state | tenant: candidate, candidates: [candidate | candidates]}}

      %{tenant: tenant} = state ->
        {{:ok, tenant}, state}
    end)
  end

  def candidates(agent), do: Agent.get(agent, &Enum.reverse(&1.candidates))
end
