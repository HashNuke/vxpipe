defmodule Vxpipe.AgentRuntime.TestModelProvider do
  @behaviour Vxpipe.AgentRuntime.ModelProvider

  alias Vxpipe.AgentRuntime.ModelResponse

  @impl true
  def generate(model, request) do
    send(Map.fetch!(model, :test_owner), {:model_provider_process, self(), request})

    case Map.get(model, :mode, :reply) do
      :reply -> ModelResponse.new(text: Map.fetch!(model, :reply))
      :block -> await_release(model)
      :scripted -> await_scripted_reply()
    end
  end

  defp await_release(model) do
    receive do
      :release -> ModelResponse.new(text: Map.get(model, :reply, "released"))
    end
  end

  defp await_scripted_reply do
    receive do
      {:test_model_response, response} -> response
    end
  end
end
