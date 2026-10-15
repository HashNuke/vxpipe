defmodule Vxpipe.Gateway.Telephony.CarrierCleanup do
  @moduledoc """
  Owner-held carrier registration and final-usage acknowledgement state.

  Storage success never supplies remote termination evidence. The original Leg
  combines its independent carrier and command-drainage proof with this helper's
  immutable persistence acknowledgement before acknowledging the tracker.
  """

  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor}
  alias Vxpipe.Gateway.Telephony.LegUsage

  @supervisor Vxpipe.Gateway.AdmissionTaskSupervisor
  @keys [:tenant_key, :call_id, :room_id, :incarnation_id]
  @terminal [:succeeded, :failed, :cancelled, :unknown]
  @derive {Inspect, only: [:binding, :persisted?, :acknowledged?, :tracker_lost?]}
  defstruct [
    :owner,
    :binding,
    :tracker,
    :tracker_monitor,
    :task,
    :batch,
    :retry,
    calls_options: [],
    timeout_ms: 5_000,
    retry_ms: 250,
    task_result: nil,
    persisted?: false,
    acknowledged?: false,
    tracker_lost?: false
  ]

  @doc """
  Registers the original carrier owner with the existing exact tracker.

  Validated attachment failure returns `{:error, :cleanup_unavailable, state}`;
  that detached state can persist final usage but cannot acknowledge membership.
  Invalid bindings or options return an error without persistence state.
  """
  def attach(binding, kind, expected_anchor, options \\ []) do
    with {:ok, anchor} <- exact_anchor(binding, expected_anchor),
         true <- kind in [:incoming_leg, :outgoing_leg],
         :ok <- valid_options(options) do
      attach_validated(kind, %__MODULE__{
        owner: self(),
        binding: anchor,
        calls_options: Keyword.get(options, :calls_options, []),
        timeout_ms: Keyword.get(options, :timeout_ms, 5_000),
        retry_ms: Keyword.get(options, :retry_ms, 250)
      })
    else
      {:error, :invalid_cleanup_binding} = error -> error
      {:error, :invalid_cleanup_options} = error -> error
      _ -> {:error, :cleanup_unavailable}
    end
  end

  @doc "Storage evidence only; does not establish carrier termination or tracker completion."
  def final_usage_stored?(%__MODULE__{} = state, usage) do
    owner(state) == :ok and state.persisted? and is_nil(state.task) and is_nil(state.retry) and
      not is_nil(state.batch) and final_usage(usage, state.binding) == :ok and
      matching_batch(state.batch, usage) == :ok
  end

  def begin_final(%__MODULE__{} = state, usage) do
    with :ok <- owner(state),
         :ok <- final_usage(usage, state.binding),
         :ok <- matching_batch(state.batch, usage) do
      state = %{state | batch: state.batch || usage}
      {:ok, if(state.task || state.retry || state.persisted?, do: state, else: start_task(state))}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  def acknowledge(%__MODULE__{} = state, usage, carrier_proof, commands_drained?) do
    with :ok <- owner(state),
         :ok <- tracker_available(state),
         true <- carrier_proof in [:carrier_ended, :not_submitted] and commands_drained? == true,
         true <- final_usage_stored?(state, usage),
         :ok <- CallCleanup.acknowledge(state.tracker, self(), :complete) do
      {:ok, %{state | acknowledged?: true}}
    else
      {:error, reason} when reason in [:invalid_cleanup_owner, :cleanup_unavailable] ->
        {:error, reason, state}

      _ ->
        {:error, :cleanup_not_ready, state}
    end
  catch
    :exit, _ -> {:error, :cleanup_unavailable, %{state | tracker_lost?: true}}
  end

  def status(%__MODULE__{tracker_lost?: true}), do: :unavailable
  def status(%__MODULE__{acknowledged?: true}), do: :acknowledged
  def status(%__MODULE__{persisted?: true}), do: :stored
  def status(%__MODULE__{task: %Task{}}), do: :storing
  def status(%__MODULE__{retry: {_token, _timer}}), do: :retrying
  def status(%__MODULE__{}), do: :idle

  def handle_info(%__MODULE__{owner: owner} = state, message) when owner == self(),
    do: handle_owned_info(state, message)

  def handle_info(%__MODULE__{}, _message), do: :unhandled

  defp handle_owned_info(%{task: %Task{ref: ref}} = state, {ref, result}),
    do: {:handled, %{state | task_result: if(result == :ok, do: :ok, else: :error)}}

  defp handle_owned_info(
         %{task: %Task{ref: ref, pid: pid}} = state,
         {:DOWN, ref, :process, pid, reason}
       ) do
    success? = state.task_result == :ok and reason == :normal
    state = %{state | task: nil, task_result: nil, persisted?: success?}
    {:handled, if(success?, do: state, else: schedule_retry(state))}
  end

  defp handle_owned_info(%{retry: {token, _timer}} = state, {:carrier_cleanup_retry, token}),
    do: {:handled, start_task(%{state | retry: nil})}

  defp handle_owned_info(
         %{tracker_monitor: ref, tracker: tracker} = state,
         {:DOWN, ref, :process, tracker, _reason}
       ),
       do: {:handled, %{state | tracker_lost?: true}}

  defp handle_owned_info(_state, _message), do: :unhandled

  defp attach_validated(kind, state) do
    case CallCleanupSupervisor.lookup(state.binding) do
      {:ok, tracker} -> register(tracker, kind, state)
      _ -> detached(state)
    end
  catch
    :exit, _ -> detached(state)
  end

  defp register(tracker, kind, state) do
    monitor = Process.monitor(tracker)

    case register_owner(tracker, kind, state.binding) do
      :ok ->
        {:ok, %{state | tracker: tracker, tracker_monitor: monitor}}

      _ ->
        Process.demonitor(monitor, [:flush])
        detached(state)
    end
  end

  defp detached(state), do: {:error, :cleanup_unavailable, %{state | tracker_lost?: true}}

  defp register_owner(tracker, kind, anchor) do
    if CallCleanup.snapshot(tracker).binding == anchor,
      do: CallCleanup.register(tracker, kind, self()),
      else: {:error, :binding_mismatch}
  catch
    :exit, _ -> {:error, :cleanup_unavailable}
  end

  defp start_task(state) do
    batch = state.batch
    options = state.calls_options
    timeout = state.timeout_ms

    task =
      Task.Supervisor.async_nolink(@supervisor, fn ->
        # Establish the deadline before storage begins, including when the original
        # owner dies before async_nolink returns. No owner mailbox is needed.
        {:ok, timer} = :timer.kill_after(timeout, self())

        try do
          LegUsage.persist_final(batch, options)
        after
          :timer.cancel(timer)
        end
      end)

    %{state | task: task, task_result: nil}
  catch
    :exit, _ -> schedule_retry(state)
  end

  defp schedule_retry(state) do
    token = make_ref()
    timer = Process.send_after(self(), {:carrier_cleanup_retry, token}, state.retry_ms)
    %{state | retry: {token, timer}, retry_ms: min(max(state.retry_ms * 2, 1), 5_000)}
  end

  defp owner(%{owner: owner}) when owner == self(), do: :ok
  defp owner(_), do: {:error, :invalid_cleanup_owner}
  defp tracker_available(%{tracker_lost?: false}), do: :ok
  defp tracker_available(_), do: {:error, :cleanup_unavailable}

  defp matching_batch(nil, _usage), do: :ok

  defp matching_batch(%LegUsage{} = original, %LegUsage{} = current) do
    if original.attempt == current.attempt and original.observations == current.observations,
      do: :ok,
      else: {:error, :usage_changed}
  end

  defp matching_batch(_, _), do: {:error, :usage_changed}

  defp final_usage(%LegUsage{attempt: %{terminal?: true}} = usage, binding) do
    attempt = usage.attempt

    anchor = %{
      tenant_key: attempt.tenant_id,
      call_id: attempt.call_id,
      room_id: attempt.room_id,
      incarnation_id: attempt.incarnation_id
    }

    cond do
      anchor != binding -> {:error, :invalid_usage_binding}
      Enum.any?(usage.observations, &(&1.outcome in @terminal)) -> :ok
      true -> {:error, :usage_not_final}
    end
  end

  defp final_usage(_, _), do: {:error, :usage_not_final}

  defp exact_anchor(binding, expected) when is_map(binding) and is_map(expected) do
    anchor = Map.take(binding, @keys)

    if map_size(anchor) == 4 and anchor == Map.take(expected, @keys) and
         Enum.all?(Map.values(anchor), &(is_binary(&1) and byte_size(&1) in 1..256)),
       do: {:ok, anchor},
       else: {:error, :invalid_cleanup_binding}
  end

  defp exact_anchor(_, _), do: {:error, :invalid_cleanup_binding}

  defp valid_options(options) when is_list(options) do
    if Keyword.keyword?(options),
      do: validate_options(options),
      else: {:error, :invalid_cleanup_options}
  end

  defp valid_options(_), do: {:error, :invalid_cleanup_options}

  defp validate_options(options) do
    timeout = Keyword.get(options, :timeout_ms, 5_000)
    retry = Keyword.get(options, :retry_ms, 250)
    calls_options = Keyword.get(options, :calls_options, [])

    if is_integer(timeout) and timeout in 1..30_000 and is_integer(retry) and retry in 0..5_000 and
         is_list(calls_options) and Keyword.keyword?(calls_options),
       do: :ok,
       else: {:error, :invalid_cleanup_options}
  end
end
