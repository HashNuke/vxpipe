defmodule Vxpipe.CallEngine.TranscriptRouter.PolicyPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Candidate}

  def request(router, %Candidate{} = candidate, options) do
    with :ok <- validate_options(options),
         :ok <- Authority.validate_candidate(candidate.authority, candidate, remaining(options)),
         do: GenServer.call(router, {:prepare_policy, candidate, options}, remaining(options))
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def begin(state, candidate, options) do
    with :ok <- validate_options(options),
         true <- Authority.whereis(state.identity.incarnation_id) == candidate.authority,
         true <- state.current == candidate.base_snapshot,
         :ok <- compatible(state.pending_policy, options) do
      pending = (state.pending_policy || lease(options)) |> Map.put(:candidate, candidate)
      state = %{state | pending_policy: pending}
      {:ok, %{token: pending.token, resources: [prepared_resource(state)]}, state}
    else
      false -> {:error, :stale_candidate}
      {:error, _reason} = error -> error
    end
  end

  def resource(state, snapshot) do
    interval = if snapshot, do: snapshot.intervals.speech_to_text
    %{state.readiness_resource | policy_interval: interval}
  end

  def readiness(%{pending_policy: %{token: token} = pending} = state, token) do
    cond do
      pending.failed? or pending.deadline_ms <= now() -> {:ok, prepared_resource(state), :failed}
      pending.candidate.base_snapshot != state.current -> {:error, :unavailable}
      true -> {:ok, prepared_resource(state), :ready}
    end
  end

  def readiness(%{readiness_resource: %{binding: {_id, :prepared_policy, token}}} = state, token),
    do: {:ok, resource(state, state.current), :ready}

  def readiness(_state, _token), do: {:error, :unavailable}

  def install(%{pending_policy: nil} = state, _snapshot), do: {:ok, state}

  def install(state, snapshot) do
    pending = state.pending_policy

    if pending.candidate.snapshot == snapshot do
      if not pending.failed? and pending.deadline_ms > now() and
           pending.candidate.base_snapshot == state.current do
        resource = prepared_resource(state)
        release(pending)
        {:ok, %{state | pending_policy: nil, readiness_resource: resource}}
      else
        {:error, :policy_not_ready}
      end
    else
      {:ok, state}
    end
  end

  def discard(%{pending_policy: %{token: token} = pending} = state, token) do
    release(pending)
    {:ok, %{state | pending_policy: nil}}
  end

  def discard(_state, _token), do: {:error, :stale_preparation}

  def fail(%{pending_policy: %{failed?: false} = pending} = state) do
    release(pending)
    send(pending.owner, {:vxpipe_transcript_policy_failed, self(), pending.token})
    %{state | pending_policy: %{pending | failed?: true}}
  end

  def fail(state), do: state

  defp prepared_resource(state) do
    pending = state.pending_policy
    desired = resource(state, pending.candidate.snapshot)

    if desired == resource(state, state.current),
      do: desired,
      else: %{desired | binding: {state.identity.incarnation_id, :prepared_policy, pending.token}}
  end

  defp compatible(nil, _options), do: :ok

  defp compatible(pending, options) do
    if not pending.failed? and pending.owner == Keyword.fetch!(options, :owner) and
         pending.attempt_id == Keyword.fetch!(options, :attempt_id) and
         pending.deadline_ms == Keyword.fetch!(options, :deadline_ms),
       do: :ok,
       else: {:error, :preparation_conflict}
  end

  defp lease(options) do
    token = make_ref()
    deadline = Keyword.fetch!(options, :deadline_ms)
    owner = Keyword.fetch!(options, :owner)

    %{
      token: token,
      owner: owner,
      monitor: Process.monitor(owner),
      attempt_id: Keyword.fetch!(options, :attempt_id),
      deadline_ms: deadline,
      failed?: false,
      timer:
        Process.send_after(self(), {:transcript_policy_expired, token}, max(deadline - now(), 0))
    }
  end

  defp release(pending) do
    Process.cancel_timer(pending.timer)
    Process.demonitor(pending.monitor, [:flush])
    :ok
  end

  defp validate_options(options) do
    owner = Keyword.get(options, :owner)
    attempt = Keyword.get(options, :attempt_id)
    deadline = Keyword.get(options, :deadline_ms)

    if is_pid(owner) and is_binary(attempt) and byte_size(attempt) in 1..128 and
         is_integer(deadline) and deadline > now(), do: :ok, else: {:error, :invalid_preparation}
  end

  defp remaining(options), do: max(Keyword.fetch!(options, :deadline_ms) - now(), 1)
  defp now, do: System.monotonic_time(:millisecond)
end
