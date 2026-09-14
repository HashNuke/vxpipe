defmodule Vxpipe.Gateway.Media.RoomAudioEgress.PolicyPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Candidate}
  alias Vxpipe.CallEngine.RoomMixer
  alias Vxpipe.CallEngine.RoomMixer.Subscription
  alias Vxpipe.Gateway.Media.{OutputArbiter, SharedOutputPipeline}
  alias Vxpipe.Gateway.Media.RoomAudioEgress.{PipelineLifecycle, Readiness}

  def request(egress, %Candidate{} = candidate, %Subscription{} = subscription, options) do
    with :ok <- validate_options(options),
         :ok <- Authority.validate_candidate(candidate.authority, candidate, remaining(options)),
         {:ok, binding} <-
           GenServer.call(
             egress,
             {:output_preparation_binding, candidate, subscription, options},
             remaining(options)
           ),
         :ok <- OutputArbiter.confirm_hold(binding.output, Keyword.fetch!(options, :generation)),
         :ok <- Subscription.confirm_subscriber(subscription, egress),
         :ok <- binding.engine.hold_room_audio(subscription, Keyword.fetch!(options, :generation)),
         {:ok, prepared} <-
           GenServer.call(
             egress,
             {:prepare_policy, candidate, subscription, options},
             remaining(options)
           ),
         {:ok, resources} <- Readiness.resources(egress, prepared.token) do
      {:ok, Map.put(prepared, :resources, resources)}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def begin(state, candidate, subscription, options) do
    with :ok <- validate(state, candidate, subscription, options),
         do: prepare(state, candidate, subscription, options)
  end

  def preparation_binding(state, candidate, subscription, options) do
    with :ok <- validate(state, candidate, subscription, options),
         do: {:ok, %{engine: state.engine, output: output(state)}}
  end

  defp validate(state, candidate, subscription, options) do
    with :ok <- validate_options(options),
         true <- state.pipeline == SharedOutputPipeline,
         true <- Authority.whereis(state.identity.incarnation_id) == candidate.authority,
         true <- state.policy == candidate.base_snapshot,
         true <- valid_subscription?(state, subscription),
         :ok <- compatible(state.pending_policy, subscription, options) do
      :ok
    else
      false -> {:error, :stale_candidate}
      {:error, _reason} = error -> error
    end
  end

  defp prepare(%{pending_policy: nil} = state, candidate, subscription, options) do
    with {:ok, change, pipeline} <- prepare_pipeline(state, options) do
      token = make_ref()
      owner = Keyword.fetch!(options, :owner)
      deadline = Keyword.fetch!(options, :deadline_ms)

      pending = %{
        token: token,
        owner: owner,
        monitor: Process.monitor(owner),
        timer:
          Process.send_after(self(), {:output_policy_expired, token}, max(deadline - now(), 0)),
        deadline_ms: deadline,
        attempt_id: Keyword.fetch!(options, :attempt_id),
        generation: Keyword.fetch!(options, :generation),
        candidate: candidate,
        subscription: subscription,
        change: change,
        pipeline: pipeline,
        failed?: false,
        ready?: false,
        evidence: nil
      }

      state = %{
        state
        | pending_policy: pending,
          pipeline_generation:
            if(pipeline, do: pipeline.pipeline_generation, else: state.pipeline_generation)
      }

      {:ok, %{token: token, change: change}, state}
    end
  end

  defp prepare(state, candidate, subscription, _options) do
    pending = %{
      state.pending_policy
      | candidate: candidate,
        subscription: subscription,
        ready?: false
    }

    {:ok, %{token: pending.token, change: pending.change}, %{state | pending_policy: pending}}
  end

  defp prepare_pipeline(%{pipeline_pid: pipeline}, _options) when is_pid(pipeline),
    do: {:ok, :retain, nil}

  defp prepare_pipeline(state, options) do
    staged = %{
      state
      | pending_policy: nil,
        pipeline_options: Keyword.put(state.pipeline_options, :preparation, options)
    }

    with {:ok, pipeline} <- PipelineLifecycle.launch(staged), do: {:ok, :start, pipeline}
  end

  def binding(%{pending_policy: %{token: token} = pending} = state, token) do
    cond do
      pending.failed? or pending.deadline_ms <= now() -> failed_binding(pending)
      pending.candidate.base_snapshot != state.policy -> {:error, :unavailable}
      true -> {:ok, prospective_binding(state)}
    end
  end

  def binding(%{readiness_resource: %{binding: {_id, :prepared_policy, token}}} = state, token),
    do: {:ok, Readiness.binding(state)}

  def binding(_state, _token), do: {:error, :unavailable}

  def confirm(state, token, expected, resource, status, dependencies) do
    with {:ok, current} <- binding(state, token),
         true <- Readiness.same_binding?(current, expected) do
      state =
        case state.pending_policy do
          %{token: ^token} = pending ->
            %{
              state
              | pending_policy: %{
                  pending
                  | ready?: status == :ready,
                    evidence: {resource, dependencies}
                }
            }

          _adopted ->
            state
        end

      {:ok, state}
    else
      _changed -> {:error, :unavailable}
    end
  end

  def install(%{pending_policy: nil} = state, _snapshot), do: {:continue, state}

  def install(state, snapshot) do
    if state.pending_policy.candidate.snapshot == snapshot do
      commit(state, snapshot)
    else
      {:continue, state}
    end
  end

  defp commit(state, snapshot) do
    pending = state.pending_policy

    with true <-
           not pending.failed? and pending.ready? and pending.deadline_ms > now() and
             pending.candidate.base_snapshot == state.policy,
         :ok <- OutputArbiter.confirm_hold(output(state), pending.generation, true),
         :ok <- activate(state, pending) do
      target = pending.pipeline || state
      binding = prospective_binding(state)
      release_lease(pending)
      Enum.each(state.ready_waiters, &GenServer.reply(&1, :ok))

      {:ok,
       %{
         state
         | pending_policy: nil,
           policy: snapshot,
           subscription: pending.subscription,
           pipeline_id: target.pipeline_id,
           pipeline_pid: target.pipeline_pid,
           pipeline_monitor: target.pipeline_monitor,
           pipeline_ready?: target.pipeline_ready?,
           ready_waiters: [],
           readiness_resource: %{target.readiness_resource | binding: binding.resource.binding}
       }}
    else
      _not_ready -> {:error, :policy_not_ready, state}
    end
  end

  defp activate(state, %{change: :retain} = pending) do
    expected = route(pending)

    case SharedOutputPipeline.readiness(state.pipeline_pid) do
      {:ok, ^expected, :ready} -> :ok
      _changed -> {:error, :stale_preparation}
    end
  end

  defp activate(_state, pending) do
    SharedOutputPipeline.activate(
      pending.pipeline.pipeline_pid,
      route(pending),
      pending.generation
    )
  end

  defp route(pending) do
    {_resource, dependencies} = pending.evidence
    Enum.find(dependencies, &(&1.kind == :room_output_binding))
  end

  def discard(%{pending_policy: %{token: token} = pending} = state, token) do
    cleanup(pending)
    {:ok, %{state | pending_policy: nil}}
  end

  def discard(_state, _token), do: {:error, :stale_preparation}

  def fail(%{pending_policy: nil} = state), do: state
  def fail(%{pending_policy: %{failed?: true}} = state), do: state

  def fail(state) do
    pending = state.pending_policy
    cleanup(pending)
    send(pending.owner, {:vxpipe_room_output_policy_failed, self(), pending.token})
    %{state | pending_policy: %{pending | failed?: true, ready?: false}}
  end

  def pipeline_ready(state) do
    pending = state.pending_policy
    %{state | pending_policy: %{pending | pipeline: %{pending.pipeline | pipeline_ready?: true}}}
  end

  defp prospective_binding(state) do
    pending = state.pending_policy
    target = pending.pipeline || state

    desired =
      Readiness.binding(%{
        target
        | policy: pending.candidate.snapshot,
          subscription: pending.subscription
      })

    if Readiness.same_binding?(desired, Readiness.binding(state)) do
      desired
    else
      %{
        desired
        | resource: %{
            desired.resource
            | binding: {state.connection_id, :prepared_policy, pending.token}
          }
      }
    end
  end

  defp failed_binding(%{evidence: {resource, dependencies}}),
    do: {:failed, resource, dependencies}

  defp failed_binding(_pending), do: {:error, :unavailable}

  defp valid_subscription?(state, subscription) do
    subscription.purpose == :participant and subscription.id == state.subscription_id and
      subscription.tenant_id == state.identity.tenant_id and
      subscription.room_id == state.identity.room_id and
      subscription.incarnation_id == state.identity.incarnation_id and
      subscription.recipient_participant_id == state.identity.participant_id and
      subscription.mixer == RoomMixer.whereis(state.identity.incarnation_id) and
      (is_nil(state.subscription) or same_subscription?(state.subscription, subscription))
  end

  defp same_subscription?(left, right),
    do: Map.drop(left, [:prepared_policy_token]) == Map.drop(right, [:prepared_policy_token])

  defp compatible(nil, _subscription, _options), do: :ok

  defp compatible(pending, subscription, options) do
    if not pending.failed? and pending.owner == Keyword.fetch!(options, :owner) and
         pending.attempt_id == Keyword.fetch!(options, :attempt_id) and
         pending.deadline_ms == Keyword.fetch!(options, :deadline_ms) and
         pending.generation == Keyword.fetch!(options, :generation) and
         same_subscription?(pending.subscription, subscription),
       do: :ok,
       else: {:error, :preparation_conflict}
  end

  defp cleanup(pending) do
    release_lease(pending)

    if pending.pipeline do
      discard_pipeline(pending.pipeline)
      PipelineLifecycle.stop(pending.pipeline)
    end

    :ok
  end

  defp discard_pipeline(pipeline) do
    SharedOutputPipeline.discard(pipeline.pipeline_pid)
  catch
    :exit, _reason -> :ok
  end

  defp release_lease(pending) do
    Process.cancel_timer(pending.timer)
    Process.demonitor(pending.monitor, [:flush])
    :ok
  end

  def output(state), do: Keyword.get(state.pipeline_options, :output_sink)

  defp validate_options(options) do
    owner = Keyword.get(options, :owner)
    attempt = Keyword.get(options, :attempt_id)
    deadline = Keyword.get(options, :deadline_ms)
    generation = Keyword.get(options, :generation)

    if is_pid(owner) and is_binary(attempt) and byte_size(attempt) in 1..128 and
         is_integer(deadline) and deadline > now() and is_integer(generation) and generation > 0,
       do: :ok,
       else: {:error, :invalid_preparation}
  end

  defp remaining(options), do: min(max(Keyword.fetch!(options, :deadline_ms) - now(), 1), 5_000)
  defp now, do: System.monotonic_time(:millisecond)
end
