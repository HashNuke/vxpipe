defmodule Vxpipe.CallEngine.Tool.Invocation do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Tool.{
    Context,
    InvocationBinding,
    InvocationCompletion,
    InvocationExecution
  }

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :invocation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec begin(GenServer.server()) :: :ok | {:error, :already_started | :unavailable}
  def begin(invocation) do
    GenServer.call(invocation, :begin, 1_000)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    with {:ok, state} <- configuration(options) do
      {:ok, Map.merge(state, %{task: nil, timer: nil})}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call(:begin, _from, %{task: nil} = state) do
    task =
      Task.async(fn ->
        InvocationExecution.run(
          state.binding,
          state.arguments,
          state.context,
          state.maximum_result_bytes
        )
      end)

    timer = Process.send_after(self(), :vxpipe_tool_invocation_timeout, state.timeout_ms)
    {:reply, :ok, %{state | task: task, timer: timer}}
  end

  def handle_call(:begin, _from, state), do: {:reply, {:error, :already_started}, state}

  @impl true
  def handle_info({reference, outcome}, %{task: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    cancel_timer(state.timer)
    report(outcome, state)
    {:stop, :normal, %{state | task: nil, timer: nil}}
  end

  def handle_info(:vxpipe_tool_invocation_timeout, state) do
    stop_task(state.task)
    report({:error, :unknown}, state)
    {:stop, :normal, %{state | task: nil, timer: nil}}
  end

  def handle_info({:DOWN, reference, :process, _pid, _reason}, %{task: %{ref: reference}} = state) do
    cancel_timer(state.timer)
    report({:error, :tool_failed}, state)
    {:stop, :normal, %{state | task: nil, timer: nil}}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{task: nil}), do: :ok

  def terminate(_reason, state) do
    stop_task(state.task)
    :ok
  end

  defp configuration(options) do
    with {:ok, options} <-
           Keyword.validate(options, [
             :invocation_id,
             :binding,
             :arguments,
             :context,
             :reply_to,
             :timeout_ms,
             :maximum_result_bytes
           ]),
         invocation_id when is_binary(invocation_id) and invocation_id != "" <-
           Keyword.get(options, :invocation_id),
         %InvocationBinding{} = binding <- Keyword.get(options, :binding),
         true <- InvocationBinding.valid?(binding),
         arguments when is_map(arguments) <- Keyword.get(options, :arguments),
         %Context{} = context <- Keyword.get(options, :context),
         reply_to when is_pid(reply_to) <- Keyword.get(options, :reply_to),
         timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 <-
           Keyword.get(options, :timeout_ms),
         maximum_result_bytes
         when is_integer(maximum_result_bytes) and maximum_result_bytes > 0 <-
           Keyword.get(options, :maximum_result_bytes) do
      {:ok,
       %{
         invocation_id: invocation_id,
         binding: binding,
         arguments: arguments,
         context: %{context | tool_call_id: invocation_id},
         reply_to: reply_to,
         timeout_ms: timeout_ms,
         maximum_result_bytes: maximum_result_bytes
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  defp report(outcome, state) do
    completion = %InvocationCompletion{
      invocation_id: state.invocation_id,
      tool_name: state.binding.name,
      conversation_mode: state.binding.conversation_mode,
      context: state.context,
      outcome: normalize_outcome(outcome)
    }

    send(state.reply_to, {:vxpipe_tool_invocation_finished, self(), completion})
  end

  defp normalize_outcome({:ok, _result} = outcome), do: outcome
  defp normalize_outcome({:error, :invalid_result} = outcome), do: outcome
  defp normalize_outcome({:error, :unknown} = outcome), do: outcome
  defp normalize_outcome(_outcome), do: {:error, :tool_failed}

  defp stop_task(nil), do: :ok

  defp stop_task(task) do
    _ = Task.shutdown(task, :brutal_kill)
    :ok
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer, async: true, info: false)
end
