defmodule Vxpipe.CallEngine.TestAgentRuntimeModelProvider do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.ModelProvider

  @impl true
  def generate(_model, _request), do: {:error, :unexpected_buffered_generation}

  @impl true
  def stream(model, request, emit) do
    send(Map.fetch!(model, :owner), {:test_agent_runtime_stream, self(), request})
    await_response(emit)
  end

  defp await_response(emit) do
    receive do
      {:test_agent_runtime_delta, text} ->
        :ok = emit.(text)
        await_response(emit)

      {:test_agent_runtime_response, response} ->
        response
    end
  end
end
