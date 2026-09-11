defmodule Vxpipe.Calls.TestArtifactRepository do
  use Agent

  @behaviour Vxpipe.Calls.ArtifactRepository

  def start_link(_options), do: Agent.start_link(fn -> %{artifacts: [], operations: []} end)

  def repository(agent), do: {__MODULE__, agent}
  def operations(agent), do: Agent.get(agent, &Enum.reverse(&1.operations))

  @impl true
  def store_call_artifact(agent, artifact) do
    Agent.update(agent, fn state ->
      %{
        state
        | artifacts: [artifact | state.artifacts],
          operations: [{:store, artifact.id} | state.operations]
      }
    end)

    {:ok, artifact}
  end

  @impl true
  def fetch_call_artifacts(agent, tenant_key, call_id) do
    Agent.get_and_update(agent, fn state ->
      artifacts =
        state.artifacts
        |> Enum.filter(&(&1.tenant_key == tenant_key and &1.call_id == call_id))
        |> Enum.sort_by(& &1.id)

      {{:ok, artifacts},
       %{state | operations: [{:fetch, tenant_key, call_id} | state.operations]}}
    end)
  end

  @impl true
  def fetch_call_artifact(agent, tenant_key, call_id, artifact_id) do
    Agent.get_and_update(agent, fn state ->
      result =
        case Enum.find(state.artifacts, fn artifact ->
               artifact.tenant_key == tenant_key and artifact.call_id == call_id and
                 artifact.id == artifact_id
             end) do
          nil -> {:error, :call_artifact_not_found}
          artifact -> {:ok, artifact}
        end

      {result,
       %{
         state
         | operations: [
             {:fetch_one, tenant_key, call_id, artifact_id} | state.operations
           ]
       }}
    end)
  end
end
