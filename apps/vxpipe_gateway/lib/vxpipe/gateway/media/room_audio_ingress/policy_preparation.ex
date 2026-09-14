defmodule Vxpipe.Gateway.Media.RoomAudioIngress.PolicyPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Candidate, Effective, Intervals}
  alias Vxpipe.Gateway.Media.RoomAudioIngress.{PipelineLifecycle, Readiness}

  def request(ingress, %Candidate{} = candidate, track, options) do
    with :ok <- validate_options(options),
         :ok <- Authority.validate_candidate(candidate.authority, candidate, remaining(options)),
         {:ok, prepared} <-
           GenServer.call(ingress, {:prepare_policy, candidate, options}, remaining(options)) do
      finish_request(ingress, prepared, track)
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp finish_request(_ingress, %{change: :disable} = prepared, _track),
    do: {:ok, Map.put(prepared, :resources, [])}

  defp finish_request(ingress, prepared, track) do
    with :ok <- Readiness.prepare_track(ingress, track, prepared.token),
         {:ok, resources} <- Readiness.resources(ingress, prepared.token) do
      {:ok, Map.put(prepared, :resources, resources)}
    else
      {:error, _reason} = error ->
        _ = GenServer.call(ingress, {:discard_policy, prepared.token}, 1_000)
        error
    end
  end

  def begin(state, candidate, options) do
    with :ok <- validate_options(options),
         true <- Authority.whereis(state.identity.incarnation_id) == candidate.authority,
         true <- state.policy == candidate.base_snapshot do
      begin_current(state, candidate, options)
    else
      false -> {:error, :stale_candidate}
      {:error, _reason} = error -> error
    end
  end

  defp begin_current(%{pending_policy: nil} = state, candidate, options) do
    change = change(state, candidate.snapshot)

    with {:ok, pipeline} <- prepare_pipeline(state, candidate.snapshot, change) do
      token = make_ref()
      owner = Keyword.fetch!(options, :owner)
      deadline = Keyword.fetch!(options, :deadline_ms)

      pending = %{
        token: token,
        candidate: candidate,
        owner: owner,
        attempt_id: Keyword.fetch!(options, :attempt_id),
        deadline_ms: deadline,
        monitor: Process.monitor(owner),
        timer:
          Process.send_after(self(), {:input_policy_expired, token}, max(deadline - now(), 0)),
        change: change,
        pipeline: pipeline,
        ready?: false,
        failed?: false
      }

      generation = if pipeline, do: pipeline.pipeline_generation, else: state.pipeline_generation
      state = %{state | pending_policy: pending, pipeline_generation: generation}
      {:ok, %{token: token, change: change}, state}
    end
  end

  defp begin_current(state, candidate, options) do
    pending = state.pending_policy

    if pending.owner == Keyword.fetch!(options, :owner) and
         pending.attempt_id == Keyword.fetch!(options, :attempt_id) and
         pending.deadline_ms == Keyword.fetch!(options, :deadline_ms) and not pending.failed? and
         pending.change == change(state, candidate.snapshot) and
         Intervals.unchanged?(
           pending.candidate.snapshot,
           candidate.snapshot,
           :audio_input,
           state.identity.participant_id
         ) do
      pipeline = if pending.pipeline, do: %{pending.pipeline | policy: candidate.snapshot}
      pending = %{pending | candidate: candidate, pipeline: pipeline}
      {:ok, %{token: pending.token, change: pending.change}, %{state | pending_policy: pending}}
    else
      {:error, :preparation_conflict}
    end
  end

  def binding(%{pending_policy: %{token: token} = pending} = state, token) do
    cond do
      pending.failed? or now() >= pending.deadline_ms or
          pending.candidate.base_snapshot != state.policy ->
        {:error, :unavailable}

      pending.change == :replace ->
        {:ok, alias_binding(Readiness.binding(pending.pipeline), token)}

      pending.change == :retain ->
        {:ok, Readiness.binding(state)}

      true ->
        {:error, :unavailable}
    end
  end

  def binding(%{adopted_policy_token: token} = state, token) when is_reference(token),
    do: {:ok, alias_binding(Readiness.binding(state), token)}

  def binding(_state, _token), do: {:error, :unavailable}

  def confirm(state, token, expected, status) do
    with {:ok, current} <- binding(state, token),
         true <- Readiness.same_binding?(expected, current) do
      state =
        case state.pending_policy do
          %{token: ^token} = pending ->
            %{
              state
              | pending_policy: %{pending | ready?: status == :ready and current.pipeline_ready?}
            }

          _adopted ->
            state
        end

      {:ok, state}
    else
      _changed -> {:error, :unavailable}
    end
  end

  def discard(%{pending_policy: %{token: token} = pending} = state, token) do
    cleanup(pending)
    {:ok, %{state | pending_policy: nil}}
  end

  def discard(_state, _token), do: {:error, :stale_preparation}

  def fail(state) do
    pending = state.pending_policy
    cleanup(pending)
    %{state | pending_policy: %{pending | pipeline: nil, ready?: false, failed?: true}}
  end

  def pipeline_ready(state) do
    pending = state.pending_policy
    %{state | pending_policy: %{pending | pipeline: %{pending.pipeline | pipeline_ready?: true}}}
  end

  def install(%{pending_policy: nil} = state, _snapshot), do: {:continue, state}

  def install(state, snapshot) do
    cond do
      state.pending_policy.candidate.snapshot == snapshot ->
        commit(state, snapshot)

      Intervals.unchanged?(state.policy, snapshot, :audio_input, state.identity.participant_id) ->
        {:continue, state}

      true ->
        {:ok, state} = discard(state, state.pending_policy.token)
        {:continue, state}
    end
  end

  defp commit(state, snapshot) do
    pending = state.pending_policy

    cond do
      pending.failed? or now() >= pending.deadline_ms ->
        {:error, :policy_not_ready, state}

      pending.change == :retain ->
        release_lease(pending)
        {:ok, %{state | pending_policy: nil, policy: snapshot}}

      pending.change == :disable ->
        with :ok <- PipelineLifecycle.stop(state) do
          release_lease(pending)
          state = PipelineLifecycle.clear(state)

          {:ok,
           %{
             state
             | pending_policy: nil,
               policy: snapshot,
               reject_received_through_ms: state.clock.()
           }}
        else
          {:error, reason} -> {:error, reason, state}
        end

      not pending.ready? or not pending.pipeline.pipeline_ready? ->
        {:error, :policy_not_ready, state}

      true ->
        adopt(state, pending)
    end
  end

  defp adopt(state, pending) do
    with :ok <- PipelineLifecycle.stop(state) do
      release_lease(pending)
      pipeline = pending.pipeline

      {:ok,
       %{
         state
         | policy: pending.candidate.snapshot,
           pipeline_id: pipeline.pipeline_id,
           pipeline_pid: pipeline.pipeline_pid,
           pipeline_monitor: pipeline.pipeline_monitor,
           pipeline_ready?: pipeline.pipeline_ready?,
           readiness_resource: pipeline.readiness_resource,
           reject_received_through_ms: state.clock.(),
           pending_policy: nil,
           adopted_policy_token: pending.token
       }}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp prepare_pipeline(state, snapshot, :replace) do
    state
    |> Map.put(:pending_policy, nil)
    |> Map.put(:policy, snapshot)
    |> PipelineLifecycle.clear()
    |> PipelineLifecycle.launch()
  end

  defp prepare_pipeline(_state, _snapshot, _change), do: {:ok, nil}

  defp change(state, snapshot) do
    cond do
      not required?(snapshot, state.identity.participant_id) ->
        :disable

      state.pipeline_pid != nil and
          Intervals.unchanged?(
            state.policy,
            snapshot,
            :audio_input,
            state.identity.participant_id
          ) ->
        :retain

      true ->
        :replace
    end
  end

  def required?(snapshot, participant) do
    MapSet.member?(snapshot.present_participant_ids, participant) and
      (snapshot.effective.record_audio or
         Enum.any?(snapshot.present_participant_ids, fn recipient ->
           participant != recipient and
             Effective.audio_route_permitted?(snapshot.effective, participant, recipient)
         end))
  end

  defp alias_binding(binding, token) do
    resource = %{binding.resource | binding: {binding.connection_id, :prepared_policy, token}}
    %{binding | resource: resource}
  end

  defp cleanup(pending) do
    release_lease(pending)
    if pending.pipeline, do: PipelineLifecycle.stop(pending.pipeline)
    :ok
  end

  defp release_lease(pending) do
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

  defp remaining(options), do: min(max(Keyword.fetch!(options, :deadline_ms) - now(), 1), 5_000)
  defp now, do: System.monotonic_time(:millisecond)
end
