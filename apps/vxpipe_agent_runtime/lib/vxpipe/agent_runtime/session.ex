defmodule Vxpipe.AgentRuntime.Session do
  @moduledoc "A supervised, single-request agent conversation boundary."

  use GenServer

  alias Vxpipe.AgentRuntime.{
    Conversation,
    Event,
    Request,
    RequestRunner,
    Result,
    SessionConfiguration
  }

  @derive {Inspect, only: [:status]}
  defstruct [
    :configuration,
    :conversation,
    :active_task,
    :active_token,
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

    with {:ok, configuration} <- SessionConfiguration.new(options) do
      {:ok,
       %__MODULE__{
         configuration: configuration,
         conversation: Conversation.new(configuration.instructions)
       }}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call({:request, input, correlation}, caller, %{status: :idle} = state) do
    with {:ok, request} <- Request.new(input, correlation) do
      emit(state.configuration.event_destination, Event.new(:request_started, correlation))
      session = self()
      token = make_ref()

      commit = fn conversation ->
        commit_conversation(session, token, conversation, state.configuration.commit_timeout_ms)
      end

      runner_options = SessionConfiguration.runner_options(state.configuration, commit)

      task =
        Task.Supervisor.async(Vxpipe.AgentRuntime.RequestSupervisor, fn ->
          RequestRunner.run(state.conversation, request, runner_options)
        end)

      {:noreply,
       %{
         state
         | status: :busy,
           active_task: task,
           active_token: token,
           caller: caller,
           correlation: correlation
       }}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:request, _input, _correlation}, _caller, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(:status, _caller, state), do: {:reply, state.status, state}

  @impl true
  def handle_info(
        {:agent_runtime_commit, worker, token, %Conversation{} = conversation},
        %{active_task: %{pid: worker}, active_token: token} = state
      ) do
    send(worker, {:agent_runtime_committed, token})
    {:noreply, %{state | conversation: conversation}}
  end

  def handle_info({reference, run_result}, %{active_task: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    {reply, event, state} = normalize_result(run_result, state.correlation, state)
    emit(state.configuration.event_destination, event)
    GenServer.reply(state.caller, reply)
    {:noreply, clear_request(state)}
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, _reason},
        %{active_task: %{ref: reference}} = state
      ) do
    result = Result.failed(:provider_unavailable, state.correlation)

    emit(
      state.configuration.event_destination,
      Event.new(:request_failed, state.correlation)
    )

    GenServer.reply(state.caller, {:ok, result})
    {:noreply, clear_request(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp normalize_result({:ok, output, %Conversation{} = conversation}, correlation, state)
       when is_binary(output) do
    result = Result.completed(output, correlation)

    {{:ok, result}, Event.new(:response_completed, correlation),
     %{state | conversation: conversation}}
  end

  defp normalize_result({:error, reason}, correlation, state) when is_atom(reason) do
    result = Result.failed(reason, correlation)
    {{:ok, result}, Event.new(:request_failed, correlation), state}
  end

  defp normalize_result(_invalid, correlation, state) do
    result = Result.failed(:invalid_provider_response, correlation)
    {{:ok, result}, Event.new(:request_failed, correlation), state}
  end

  defp clear_request(state) do
    %{
      state
      | status: :idle,
        active_task: nil,
        active_token: nil,
        caller: nil,
        correlation: nil
    }
  end

  defp commit_conversation(session, token, conversation, timeout_ms) do
    send(session, {:agent_runtime_commit, self(), token, conversation})

    receive do
      {:agent_runtime_committed, ^token} -> :ok
    after
      timeout_ms -> {:error, :commit_unavailable}
    end
  end

  defp emit(destination, event), do: send(destination, {:agent_runtime_event, event})
end
