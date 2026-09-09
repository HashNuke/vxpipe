defmodule Vxpipe.CallEngine.Tool.BackgroundInvocation do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Tool.{BackgroundCompletion, Call, Context, Executor}

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :invocation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    state = %{
      call: Keyword.fetch!(options, :call),
      context: Keyword.fetch!(options, :context),
      executor: Keyword.fetch!(options, :executor),
      reply_to: Keyword.fetch!(options, :reply_to),
      timeout_ms: Keyword.fetch!(options, :timeout_ms)
    }

    with %Call{} <- state.call,
         %Context{} <- state.context,
         %Executor{} <- state.executor,
         true <- is_pid(state.reply_to),
         true <- is_integer(state.timeout_ms) and state.timeout_ms > 0 do
      task = Task.async(fn -> Executor.execute(state.executor, state.call, state.context) end)
      timer = Process.send_after(self(), :vxpipe_background_tool_timeout, state.timeout_ms)
      {:ok, Map.merge(state, %{task: task, timer: timer})}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_info({reference, outcome}, %{task: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    cancel_timer(state.timer)
    report(outcome, state)
    {:stop, :normal, %{state | task: nil, timer: nil}}
  end

  def handle_info(:vxpipe_background_tool_timeout, state) do
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
  def terminate(_reason, %{task: task}) do
    stop_task(task)
    :ok
  end

  defp report(outcome, state) do
    completion = %BackgroundCompletion{
      call: state.call,
      context: state.context,
      outcome: normalize_outcome(outcome)
    }

    send(
      state.reply_to,
      {:vxpipe_background_invocation_finished, self(), state.call.id, completion}
    )
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
