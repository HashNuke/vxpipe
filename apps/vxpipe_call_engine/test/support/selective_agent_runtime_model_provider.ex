defmodule Vxpipe.CallEngine.TestSelectiveAgentRuntimeModelProvider do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.ModelProvider

  @spec new(keyword()) :: {:ok, map()} | {:error, :invalid_configuration}
  def new(options) do
    with {:ok, options} <- Keyword.validate(options, [:model, :owner]),
         model when is_binary(model) and model != "" <- Keyword.get(options, :model),
         false <- model == "test:unavailable",
         owner when is_pid(owner) <- Keyword.get(options, :owner) do
      prepare(model, owner)
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

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

  defp prepare("test:blocked", owner) do
    send(owner, {:test_agent_runtime_model_preparing, self()})

    receive do
      :release_test_agent_runtime_model -> {:ok, %{model: "test:blocked", owner: owner}}
    end
  end

  defp prepare("test:blocked-unavailable", owner) do
    send(owner, {:test_agent_runtime_model_preparing, self()})

    receive do
      :release_test_agent_runtime_model -> {:error, :invalid_configuration}
    end
  end

  defp prepare(model, owner), do: {:ok, %{model: model, owner: owner}}
end
