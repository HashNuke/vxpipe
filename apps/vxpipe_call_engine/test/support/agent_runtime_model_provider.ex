defmodule Vxpipe.CallEngine.TestAgentRuntimeModelProvider do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.ModelProvider

  @impl true
  def readiness(_model), do: :ready

  @spec new(keyword()) :: {:ok, map()} | {:error, :invalid_configuration}
  def new(options) do
    with {:ok, options} <- Keyword.validate(options, [:model, :owner]),
         model when is_binary(model) and model != "" <- Keyword.get(options, :model),
         owner when is_pid(owner) <- Keyword.get(options, :owner) do
      {:ok, %{model: model, owner: owner}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def generate(model, request) do
    send(Map.fetch!(model, :owner), {:test_agent_runtime_generate, self(), request})
    await_response(fn _text -> :ok end)
  end

  @impl true
  def stream(model, request, emit) do
    send(Map.fetch!(model, :owner), {:test_agent_runtime_stream, self(), request})
    await_response(emit)
  end

  defp await_response(emit) do
    receive do
      {:test_agent_runtime_delta, text, observer} ->
        result = emit.(text)
        send(observer, {:test_agent_runtime_delta_result, result})
        await_response(emit)

      {:test_agent_runtime_delta, text} ->
        :ok = emit.(text)
        await_response(emit)

      {:test_agent_runtime_response, response} ->
        response
    end
  end
end
