defmodule Vxpipe.Console.TestCallInspectionBackend do
  @moduledoc false

  @behaviour Vxpipe.Console.CallInspectionBackend

  @impl true
  def list_calls({observer, responses}, principal, options) do
    send(observer, {:list_calls, principal, options})
    Map.fetch!(responses, :list_calls)
  end

  @impl true
  def inspect_call({observer, responses}, principal, call_id, options) do
    send(observer, {:inspect_call, principal, call_id, options})
    Map.fetch!(responses, :inspect_call)
  end

  @impl true
  def inspect_live_call({observer, responses}, principal, call_id, options) do
    send(observer, {:inspect_live_call, principal, call_id, options})
    Map.fetch!(responses, :inspect_live_call)
  end
end
