defmodule Vxpipe.Calls.TestLiveInspectionSource do
  use Agent

  @behaviour Vxpipe.Calls.LiveInspectionSource

  def start_link(options) do
    Agent.start_link(fn ->
      %{snapshot: Keyword.fetch!(options, :snapshot), operations: []}
    end)
  end

  def source(server), do: {__MODULE__, server}
  def operations(server), do: Agent.get(server, &Enum.reverse(&1.operations))

  @impl true
  def fetch(server, tenant_key, call_id) do
    Agent.get_and_update(server, fn state ->
      snapshot = state.snapshot

      result =
        if snapshot.tenant_id == tenant_key and snapshot.call_id == call_id do
          {:ok, snapshot}
        else
          {:error, :call_not_live}
        end

      operation = {:fetch, tenant_key, call_id}
      {result, %{state | operations: [operation | state.operations]}}
    end)
  end
end
