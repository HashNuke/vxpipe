defmodule Vxpipe.Gateway.Media.OutputArbiter.PreparedRoom do
  @moduledoc false

  def begin(state, caller, identity, options) do
    with :ok <- validate(state, identity, options) do
      case state.prepared_room do
        nil -> create(state, caller, options)
        pending -> reuse(state, pending, caller, options)
      end
    end
  end

  def valid?(state, pending) do
    pending.deadline_ms > now() and pending.generation == state.generation and state.held? and
      pending.base_token == active_token(state)
  end

  def discard(%{prepared_room: %{binding: %{token: token}} = pending} = state, caller, token) do
    if caller in [pending.owner, pending.binding.caller],
      do: {:ok, cancel(state)},
      else: {:error, :stale_preparation}
  end

  def discard(_state, _caller, _token), do: {:error, :stale_preparation}

  def commit(
        %{prepared_room: nil, binding: %{token: token, caller: caller}} = state,
        caller,
        token,
        generation
      )
      when generation == state.generation,
      do: {:ok, state}

  def commit(
        %{prepared_room: %{binding: %{token: token, caller: caller}} = pending} = state,
        caller,
        token,
        generation
      ) do
    cond do
      generation != pending.generation or generation != state.generation ->
        {:error, :stale_output_generation}

      not valid?(state, pending) ->
        {:error, :stale_preparation}

      state.current != nil or state.pending_direct != nil or state.pending_binding != nil or
        state.clearing? or state.draining? ->
        {:error, :output_not_drained}

      true ->
        if state.binding, do: Process.demonitor(state.binding.monitor, [:flush])
        release_lease(pending)
        {:ok, %{state | prepared_room: nil, binding: pending.binding}}
    end
  end

  def commit(_state, _caller, _token, _generation), do: {:error, :stale_preparation}

  def cancel(%{prepared_room: nil} = state), do: state

  def cancel(state) do
    pending = state.prepared_room
    release_lease(pending)
    Process.demonitor(pending.binding.monitor, [:flush])
    send(pending.binding.caller, {:vxpipe_room_binding_cancelled, self(), pending.binding.token})
    %{state | prepared_room: nil}
  end

  defp create(state, caller, options) do
    owner = Keyword.fetch!(options, :owner)
    deadline = Keyword.fetch!(options, :deadline_ms)
    token = make_ref()

    pending = %{
      binding: %{
        token: token,
        caller: caller,
        monitor: Process.monitor(caller),
        identity: state.identity
      },
      owner: owner,
      owner_monitor: Process.monitor(owner),
      attempt_id: Keyword.fetch!(options, :attempt_id),
      deadline_ms: deadline,
      generation: state.generation,
      base_token: active_token(state),
      timer: Process.send_after(self(), {:prepared_room_expired, token}, max(deadline - now(), 0))
    }

    {:ok, token, %{state | prepared_room: pending}}
  end

  defp reuse(state, pending, caller, options) do
    if valid?(state, pending) and pending.binding.caller == caller and
         pending.owner == Keyword.fetch!(options, :owner) and
         pending.attempt_id == Keyword.fetch!(options, :attempt_id) and
         pending.deadline_ms == Keyword.fetch!(options, :deadline_ms) do
      {:ok, pending.binding.token, state}
    else
      {:error, :preparation_conflict}
    end
  end

  defp validate(state, identity, options) do
    owner = Keyword.get(options, :owner)
    attempt = Keyword.get(options, :attempt_id)
    deadline = Keyword.get(options, :deadline_ms)
    generation = Keyword.get(options, :generation)

    cond do
      identity != state.identity ->
        {:error, :wrong_recipient}

      not is_pid(owner) or not is_binary(attempt) or byte_size(attempt) not in 1..128 or
        not is_integer(deadline) or deadline <= now() ->
        {:error, :invalid_preparation}

      generation != state.generation ->
        {:error, :stale_output_generation}

      not state.held? ->
        {:error, :output_not_held}

      state.clearing? or state.draining? ->
        {:error, :output_not_drained}

      true ->
        :ok
    end
  end

  defp release_lease(pending) do
    Process.cancel_timer(pending.timer)
    Process.demonitor(pending.owner_monitor, [:flush])
    :ok
  end

  defp active_token(%{binding: nil}), do: nil
  defp active_token(state), do: state.binding.token
  defp now, do: System.monotonic_time(:millisecond)
end
