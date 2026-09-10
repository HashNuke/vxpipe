defmodule Vxpipe.AgentRuntime.Session do
  @moduledoc "A supervised, single-request agent conversation boundary."

  use GenServer

  alias Vxpipe.AgentRuntime.{Event, Request, Result}

  @derive {Inspect, only: [:status]}
  defstruct [
    :instructions,
    :model_provider,
    :model,
    :event_destination,
    :active_task,
    :caller,
    :correlation,
    status: :idle
  ]

  @type server :: GenServer.server()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @spec request(server(), String.t(), map(), timeout()) :: {:ok, Result.t()} | {:error, atom()}
  def request(server, input, correlation, timeout \\ 5_000) do
    GenServer.call(server, {:request, input, correlation}, timeout)
  end

  @spec status(server()) :: :idle | :busy
  def status(server), do: GenServer.call(server, :status)

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    with {:ok, options} <-
           Keyword.validate(options, [:instructions, :model_provider, :model, :event_destination]),
         instructions when is_binary(instructions) <- Keyword.get(options, :instructions),
         model_provider when is_atom(model_provider) <- Keyword.get(options, :model_provider),
         true <- Code.ensure_loaded?(model_provider),
         true <- function_exported?(model_provider, :generate, 2),
         destination when is_pid(destination) <- Keyword.get(options, :event_destination) do
      {:ok,
       %__MODULE__{
         instructions: instructions,
         model_provider: model_provider,
         model: Keyword.get(options, :model),
         event_destination: destination
       }}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call({:request, input, correlation}, caller, %{status: :idle} = state) do
    with {:ok, request} <- Request.new(input, correlation) do
      emit(state.event_destination, Event.new(:request_started, correlation))

      task =
        Task.Supervisor.async(Vxpipe.AgentRuntime.RequestSupervisor, fn ->
          state.model_provider.generate(state.model, request)
        end)

      {:noreply,
       %{state | status: :busy, active_task: task, caller: caller, correlation: correlation}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:request, _input, _correlation}, _caller, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(:status, _caller, state), do: {:reply, state.status, state}

  @impl true
  def handle_info({reference, provider_result}, %{active_task: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    {reply, event} = normalize_result(provider_result, state.correlation)
    emit(state.event_destination, event)
    GenServer.reply(state.caller, reply)
    {:noreply, clear_request(state)}
  end

  def handle_info({:DOWN, reference, :process, _pid, _reason}, %{active_task: %{ref: reference}} = state) do
    result = Result.failed(:provider_unavailable, state.correlation)
    emit(state.event_destination, Event.new(:request_failed, state.correlation))
    GenServer.reply(state.caller, {:ok, result})
    {:noreply, clear_request(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp normalize_result({:ok, output}, correlation) when is_binary(output) do
    result = Result.completed(output, correlation)
    {{:ok, result}, Event.new(:response_completed, correlation)}
  end

  defp normalize_result({:error, reason}, correlation) when is_atom(reason) do
    result = Result.failed(reason, correlation)
    {{:ok, result}, Event.new(:request_failed, correlation)}
  end

  defp normalize_result(_invalid, correlation) do
    result = Result.failed(:invalid_provider_response, correlation)
    {{:ok, result}, Event.new(:request_failed, correlation)}
  end

  defp clear_request(state) do
    %{state | status: :idle, active_task: nil, caller: nil, correlation: nil}
  end

  defp emit(destination, event), do: send(destination, {:agent_runtime_event, event})
end
