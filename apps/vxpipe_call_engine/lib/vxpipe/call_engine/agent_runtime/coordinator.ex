defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator do
  @moduledoc false

  use GenServer

  alias Vxpipe.AgentRuntime.{Event, Result, Session}
  alias Vxpipe.CallEngine.AgentRuntime.{ConversationAdmission, Correlation, OutputBuffer}
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.State
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.{Id, Telemetry}

  @call_timeout 5_000
  @cancel_timeout 1_000

  def start_link(options) do
    genserver_options = Keyword.take(options, [:name])
    coordinator_options = Keyword.delete(options, :name)
    GenServer.start_link(__MODULE__, coordinator_options, genserver_options)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :activation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec respond(GenServer.server(), SendText.t()) ::
          :ok | {:error, :queue_full | :unavailable}
  def respond(coordinator, %SendText{} = command) do
    GenServer.call(coordinator, {:respond, command}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    case configuration(options) do
      {:ok, state} -> {:ok, state}
      {:error, :invalid_configuration} -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call({:respond, command}, _from, %State{current: nil} = state) do
    case admit(command, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:held, state} -> {:reply, :ok, state}
      {:error, :unavailable} -> {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:respond, command}, _from, %State{} = state) do
    if :queue.len(state.pending) < state.maximum_pending_requests do
      {:reply, :ok, %{state | pending: :queue.in(command, state.pending)}}
    else
      {:reply, {:error, :queue_full}, state}
    end
  end

  @impl true
  def handle_info(
        {:agent_runtime_event,
         %Event{kind: :text_delta, correlation: correlation, data: %{text: text}}},
        %State{current: %{correlation: correlation}} = state
      ) do
    case OutputBuffer.push(state.current.output, text) do
      {:ok, output, segments} ->
        state = observe_first_output(text, state)
        Enum.each(segments, &emit_text(state, &1))
        {:noreply, put_in(state.current.output, output)}

      {:error, :invalid_response} ->
        state = cancel_runtime_request(state)
        {:noreply, fail_and_advance(state, :invalid_response)}
    end
  end

  def handle_info(
        {reference, result},
        %State{current: %{task: %Task{ref: reference}}} = state
      ) do
    Process.demonitor(reference, [:flush])
    {:noreply, complete_and_advance(result, state)}
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, _reason},
        %State{current: %{task: %Task{ref: reference}}} = state
      ) do
    {:noreply, fail_and_advance(state, :provider_unavailable)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp start_request(%SendText{} = command, %State{} = state) do
    request_id = Id.generate(:agent_request)
    context = tool_context(command, request_id, state.agent_participant_id)
    correlation = Correlation.new(state.invocation_registry, context)

    task =
      Task.Supervisor.async_nolink(state.request_supervisor, fn ->
        Session.request(state.session, command.content, correlation, :infinity)
      end)

    current = %{
      command: command,
      correlation: correlation,
      first_output_observed?: false,
      output: OutputBuffer.new(state.maximum_output_bytes),
      started_at: Telemetry.started_at(),
      task: task
    }

    {:ok, %{state | current: current}}
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp complete_and_advance({:ok, %Result{status: :completed, output: output}}, state)
       when is_binary(output) do
    state = observe_first_output(output, state)

    case OutputBuffer.finish(state.current.output, output) do
      {:ok, segments} ->
        Enum.each(segments, &emit_text(state, &1))
        Telemetry.model_request_stop(state.current.started_at, state.provider, :ok, true)
        send(state.owner, {:vxpipe_capability_text_complete, self(), state.current.command})
        state |> Map.put(:current, nil) |> start_next()

      {:error, :invalid_response} ->
        fail_and_advance(state, :invalid_response)
    end
  end

  defp complete_and_advance({:ok, %Result{status: :cancelled}}, state) do
    fail_and_advance(state, :interrupted)
  end

  defp complete_and_advance({:ok, %Result{status: :failed, reason: reason}}, state) do
    fail_and_advance(state, failure_reason(reason))
  end

  defp complete_and_advance(_invalid, state) do
    fail_and_advance(state, :provider_unavailable)
  end

  defp fail_and_advance(%State{current: nil} = state, _reason), do: start_next(state)

  defp fail_and_advance(%State{} = state, reason) do
    Telemetry.model_request_stop(
      state.current.started_at,
      state.provider,
      reason,
      state.current.first_output_observed?
    )

    send(state.owner, {:vxpipe_capability_failed, self(), state.current.command, reason})
    state |> Map.put(:current, nil) |> start_next()
  end

  defp start_next(%State{} = state) do
    case :queue.out(state.pending) do
      {{:value, command}, pending} ->
        state = %{state | pending: pending}

        case admit(command, state) do
          {:ok, state} ->
            state

          {:held, state} ->
            start_next(state)

          {:error, :unavailable} ->
            send(state.owner, {:vxpipe_capability_failed, self(), command, :provider_unavailable})
            start_next(state)
        end

      {:empty, _pending} ->
        state
    end
  end

  defp admit(command, state) do
    case ConversationAdmission.decide(state.invocation_registry) do
      :admit ->
        start_request(command, state)

      :hold ->
        emit_holding_response(command, state)
        {:held, state}

      {:error, :unavailable} ->
        {:error, :unavailable}
    end
  end

  defp emit_holding_response(command, state) do
    send(
      state.owner,
      {:vxpipe_capability_text, self(), command, ConversationAdmission.holding_response()}
    )

    send(state.owner, {:vxpipe_capability_text_complete, self(), command})
  end

  defp observe_first_output(text, state)
       when is_binary(text) and text != "" and not state.current.first_output_observed? do
    Telemetry.model_first_token(state.current.started_at, state.provider)
    put_in(state.current.first_output_observed?, true)
  end

  defp observe_first_output(_text, state), do: state

  defp emit_text(state, text) do
    send(state.owner, {:vxpipe_capability_text, self(), state.current.command, text})
  end

  defp cancel_runtime_request(%State{current: %{task: %Task{} = task}} = state) do
    _ = Session.cancel(state.session, @cancel_timeout)
    _ = Task.shutdown(task, :brutal_kill)
    state
  catch
    :exit, _reason -> state
  end

  defp tool_context(command, request_id, agent_participant_id) do
    %Context{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      agent_participant_id: agent_participant_id,
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id,
      agent_request_id: request_id,
      tool_call_id: nil
    }
  end

  defp failure_reason(:request_timeout), do: :provider_timeout
  defp failure_reason(:cancelled), do: :interrupted
  defp failure_reason(:provider_unavailable), do: :provider_unavailable
  defp failure_reason(_reason), do: :invalid_response

  defp configuration(options) do
    with {:ok, options} <-
           Keyword.validate(options, [
             :activation_id,
             :agent_participant_id,
             :session,
             :invocation_registry,
             :request_supervisor,
             :owner,
             :provider,
             :maximum_output_bytes,
             :maximum_pending_requests
           ]),
         activation_id when is_binary(activation_id) and activation_id != "" <-
           Keyword.get(options, :activation_id),
         agent_participant_id when is_binary(agent_participant_id) and agent_participant_id != "" <-
           Keyword.get(options, :agent_participant_id),
         session when not is_nil(session) <- Keyword.get(options, :session),
         invocation_registry when not is_nil(invocation_registry) <-
           Keyword.get(options, :invocation_registry),
         request_supervisor when not is_nil(request_supervisor) <-
           Keyword.get(options, :request_supervisor),
         owner when is_pid(owner) <- Keyword.get(options, :owner),
         maximum_output_bytes when is_integer(maximum_output_bytes) and maximum_output_bytes > 0 <-
           Keyword.get(options, :maximum_output_bytes),
         maximum_pending_requests
         when is_integer(maximum_pending_requests) and maximum_pending_requests > 0 <-
           Keyword.get(options, :maximum_pending_requests) do
      {:ok,
       %State{
         agent_participant_id: agent_participant_id,
         session: session,
         invocation_registry: invocation_registry,
         request_supervisor: request_supervisor,
         owner: owner,
         provider: Keyword.get(options, :provider, :other),
         maximum_output_bytes: maximum_output_bytes,
         maximum_pending_requests: maximum_pending_requests
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end
end
