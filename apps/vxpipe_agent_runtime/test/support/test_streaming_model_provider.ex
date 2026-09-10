defmodule Vxpipe.AgentRuntime.TestStreamingModelProvider do
  @behaviour Vxpipe.AgentRuntime.ModelProvider

  @impl true
  def generate(model, request) do
    send(Map.fetch!(model, :test_owner), {:unexpected_buffered_generation, self(), request})
    {:error, :unexpected_buffered_generation}
  end

  @impl true
  def stream(model, request, emit) do
    send(Map.fetch!(model, :test_owner), {:model_stream_process, self(), request})
    await_event(emit)
  end

  defp await_event(emit) do
    receive do
      {:test_stream_delta, text} ->
        _ = emit.(text)
        await_event(emit)

      {:test_stream_response, response} ->
        response
    end
  end
end
