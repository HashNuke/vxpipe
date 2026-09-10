defmodule Vxpipe.AgentRuntime.TestModelProvider do
  @behaviour Vxpipe.AgentRuntime.ModelProvider

  @impl true
  def generate(model, request) do
    send(Map.fetch!(model, :test_owner), {:model_provider_process, self(), request})

    case Map.get(model, :mode, :reply) do
      :reply -> {:ok, Map.fetch!(model, :reply)}
      :block -> await_release(model)
    end
  end

  defp await_release(model) do
    receive do
      :release -> {:ok, Map.get(model, :reply, "released")}
    end
  end
end
