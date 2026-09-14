defmodule Vxpipe.CallEngine.Diagnostics.AgentRuntimeModelProvider do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.ModelProvider

  alias Vxpipe.AgentRuntime.{Message, ModelRequest, ModelResponse}
  alias Vxpipe.CallEngine.Diagnostics.AgentRuntimeModelProvider.Config
  alias Vxpipe.CallEngine.Diagnostics.ModelFixture

  @spec new(keyword()) :: {:ok, Config.t()} | {:error, :invalid_configuration}
  def new(options) do
    with {:ok, options} <- Keyword.validate(options, [:fixture, :model]),
         {:ok, fixture} <- server_pid(Keyword.get(options, :fixture)),
         model when is_binary(model) and model != "" <- Keyword.get(options, :model) do
      {:ok, %Config{fixture: fixture, model: model}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def readiness(%Config{fixture: fixture}),
    do: if(Process.alive?(fixture), do: :ready, else: :failed)

  @impl true
  def streaming?(%Config{}), do: true

  @impl true
  def generate(%Config{} = config, %ModelRequest{} = request) do
    run(config, request, fn _text -> :ok end)
  end

  @impl true
  def stream(%Config{} = config, %ModelRequest{} = request, emit)
      when is_function(emit, 1) do
    run(config, request, emit)
  end

  defp run(config, request, emit) do
    with {:ok, input} <- latest_input(request.messages),
         {:ok, fixture} <- ModelFixture.take(config.fixture, input) do
      wait(fixture.delay_ms)
      response(fixture, emit)
    else
      _unavailable -> {:error, :provider_unavailable}
    end
  end

  defp response(%{scenario: scenario, response: text}, emit)
       when scenario in [:success, :delay] do
    with :ok <- emit.(text),
         {:ok, response} <- ModelResponse.new(text: text) do
      {:ok, response}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

  defp response(%{scenario: :failure}, _emit), do: {:error, :provider_unavailable}
  defp response(%{scenario: :missing}, _emit), do: {:error, :invalid_provider_response}
  defp response(_fixture, _emit), do: {:error, :invalid_provider_response}

  defp latest_input(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Message{role: :user, content: content} when is_binary(content) and content != "" -> content
      _other -> nil
    end)
    |> case do
      input when is_binary(input) -> {:ok, input}
      nil -> {:error, :invalid_request}
    end
  end

  defp wait(0), do: :ok

  defp wait(delay_ms) do
    receive do
    after
      delay_ms -> :ok
    end
  end

  defp server_pid(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) -> {:ok, pid}
      _missing -> {:error, :unavailable}
    end
  rescue
    _exception -> {:error, :unavailable}
  end
end
