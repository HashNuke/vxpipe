defmodule Vxpipe.CallEngine.RoomMixer.PolicyPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Candidate}

  alias Vxpipe.CallEngine.RoomMixer.{
    PreparedRecordings,
    PreparedSubscriptions,
    SubscriptionCatalog,
    SubscriptionReadiness
  }

  def subscriber?(state, id, token, subscriber) do
    pending =
      if state.pending_policy, do: Map.get(state.pending_policy.subscriptions.catalog.entries, id)

    Enum.any?([Map.get(state.subscriptions.entries, id), pending], fn
      %{token: ^token, subscriber: ^subscriber} -> true
      _other -> false
    end)
  end

  def gate_subscription(state, id, token, action, generation) do
    case SubscriptionCatalog.gate(
           state.subscriptions,
           id,
           token,
           action,
           generation,
           state.source_sequences
         ) do
      {{:error, :unknown_subscription}, _catalog} ->
        gate_pending(state, id, token, action, generation)

      {reply, catalog} ->
        {reply, %{state | subscriptions: catalog}}
    end
  end

  defp gate_pending(%{pending_policy: pending} = state, id, token, :hold, generation)
       when not is_nil(pending) do
    if valid?(state, pending) do
      {reply, catalog} =
        SubscriptionCatalog.gate(
          pending.subscriptions.catalog,
          id,
          token,
          :hold,
          generation,
          state.source_sequences
        )

      subscriptions = %{pending.subscriptions | catalog: catalog}
      {reply, %{state | pending_policy: %{pending | subscriptions: subscriptions}}}
    else
      {{:error, :stale_preparation}, state}
    end
  end

  defp gate_pending(state, _id, _token, _action, _generation),
    do: {{:error, :unknown_subscription}, state}

  def request(server, %Candidate{} = candidate, options) do
    with :ok <- validate_options(options),
         :ok <- Authority.validate_candidate(candidate.authority, candidate, remaining(options)),
         do: GenServer.call(server, {:prepare_policy, candidate, options}, remaining(options))
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def begin(state, candidate, options) do
    with :ok <- validate_options(options),
         true <- Authority.whereis(state.identity.incarnation_id) == candidate.authority,
         true <- state.policy == candidate.base_snapshot,
         :ok <- compatible_lease(state.pending_policy, options),
         previous =
           if(state.pending_policy,
             do: state.pending_policy.subscriptions,
             else: PreparedSubscriptions.new(state)
           ),
         {:ok, subscriptions} <-
           PreparedSubscriptions.stage(
             state,
             previous,
             candidate.snapshot,
             Keyword.get_lazy(options, :subscriptions, fn ->
               PreparedSubscriptions.options(previous)
             end)
           ) do
      pending = if state.pending_policy, do: state.pending_policy, else: lease(options)
      recordings = PreparedRecordings.capture(state, candidate.snapshot, pending.token)

      pending =
        Map.merge(pending, %{
          candidate: candidate,
          subscriptions: subscriptions,
          recordings: recordings
        })

      state = %{state | pending_policy: pending}
      resource = resource(state, candidate.snapshot)

      resource =
        if resource == resource(state, state.policy),
          do: resource,
          else: alias_resource(resource, pending.token)

      resources =
        [
          resource
          | PreparedSubscriptions.resources(
              state,
              subscriptions,
              candidate.snapshot,
              pending.token
            )
        ] ++ PreparedRecordings.resources(recordings)

      {:ok,
       %{
         token: pending.token,
         resources: resources,
         recording_subscriptions: PreparedRecordings.handles(recordings),
         subscriptions: PreparedSubscriptions.handles(subscriptions, resources, pending.token)
       }, state}
    else
      false -> {:error, :stale_candidate}
      {:error, _reason} = error -> error
    end
  end

  def resource(state, snapshot) do
    %{
      state.readiness_resource
      | policy_interval: Map.take(snapshot.intervals, [:audio_input, :audio_output, :recording])
    }
  end

  def readiness(state, token) do
    with {:ok, snapshot, _subscriptions, status} <- selection(state, token),
         do: {:ok, alias_resource(resource(state, snapshot), token), status}
  end

  def subscription_readiness(%{pending_policy: %{token: lease}} = state, lease, id, token) do
    if Map.has_key?(state.pending_policy.recordings, id) do
      with {:ok, _snapshot, _subscriptions, status} <- selection(state, lease),
           %{handle: %{token: ^token}, resource: resource} <-
             Map.fetch!(state.pending_policy.recordings, id),
           do: {:ok, resource, status},
           else: (_unavailable -> {:error, :unavailable})
    else
      participant_readiness(state, lease, id, token)
    end
  end

  def subscription_readiness(state, lease, id, token) do
    case Map.get(state.subscriptions.entries, id) do
      %{token: ^token, prepared_policy_token: ^lease} ->
        SubscriptionReadiness.fetch(state, id, token)

      _unavailable ->
        {:error, :unavailable}
    end
  end

  defp participant_readiness(state, lease, id, token) do
    with {:ok, snapshot, subscriptions, status} <- selection(state, lease),
         true <- Map.has_key?(subscriptions.selected, id),
         {:ok, resource, :ready} <-
           PreparedSubscriptions.binding(state, subscriptions, snapshot, id, token) do
      {:ok, %{resource | binding: {id, :prepared_policy, lease}}, status}
    else
      _unavailable -> {:error, :unavailable}
    end
  end

  def discard(%{pending_policy: %{token: token} = pending} = state, token) do
    cleanup(pending)
    {:ok, %{state | pending_policy: nil}}
  end

  def discard(_state, _token), do: {:error, :stale_preparation}

  def fail(%{pending_policy: nil} = state), do: state
  def fail(%{pending_policy: %{failed?: true}} = state), do: state

  def fail(state) do
    cleanup(state.pending_policy)

    send(
      state.pending_policy.owner,
      {:vxpipe_mixer_policy_failed, self(), state.pending_policy.token}
    )

    %{state | pending_policy: %{state.pending_policy | failed?: true}}
  end

  def install(%{pending_policy: nil} = state, _snapshot), do: {:ok, state}

  def install(state, snapshot) do
    pending = state.pending_policy

    if snapshot == pending.candidate.snapshot do
      if valid?(state, pending) do
        release_lease(pending)

        {:ok,
         %{
           state
           | pending_policy: nil,
             adopted_policy_token: pending.token,
             subscriptions:
               state
               |> PreparedSubscriptions.adopt(pending.subscriptions, snapshot, pending.token)
               |> PreparedRecordings.adopt(pending.recordings, pending.token)
         }}
      else
        {:error, :policy_not_ready}
      end
    else
      {:ok, state}
    end
  end

  def reserved?(%{pending_policy: nil}, _id), do: false

  def reserved?(state, id),
    do: Map.has_key?(state.pending_policy.subscriptions.catalog.entries, id)

  def down(%{pending_policy: nil} = state, _monitor), do: state

  def down(state, monitor) do
    pending = state.pending_policy

    if pending.monitor == monitor or
         PreparedSubscriptions.owns_monitor?(pending.subscriptions, monitor) or
         not PreparedSubscriptions.valid?(
           state,
           pending.subscriptions,
           pending.candidate.snapshot
         ) or not PreparedRecordings.valid?(state, pending.recordings, pending.candidate.snapshot),
       do: fail(state),
       else: state
  end

  defp selection(%{pending_policy: %{token: token} = pending} = state, token) do
    cond do
      pending.failed? or pending.deadline_ms <= now() ->
        {:ok, pending.candidate.snapshot, pending.subscriptions, :failed}

      pending.candidate.base_snapshot != state.policy ->
        {:error, :unavailable}

      true ->
        status = if valid?(state, pending), do: :ready, else: :failed
        {:ok, pending.candidate.snapshot, pending.subscriptions, status}
    end
  end

  defp selection(%{adopted_policy_token: token} = state, token) when is_reference(token),
    do: {:ok, state.policy, PreparedSubscriptions.new(state), :ready}

  defp selection(_state, _token), do: {:error, :unavailable}

  defp valid?(state, pending),
    do:
      not pending.failed? and pending.deadline_ms > now() and
        pending.candidate.base_snapshot == state.policy and
        PreparedSubscriptions.valid?(state, pending.subscriptions, pending.candidate.snapshot) and
        PreparedRecordings.valid?(state, pending.recordings, pending.candidate.snapshot)

  defp compatible_lease(nil, _options), do: :ok

  defp compatible_lease(pending, options) do
    if not pending.failed? and pending.owner == Keyword.fetch!(options, :owner) and
         pending.attempt_id == Keyword.fetch!(options, :attempt_id) and
         pending.deadline_ms == Keyword.fetch!(options, :deadline_ms),
       do: :ok,
       else: {:error, :preparation_conflict}
  end

  defp lease(options) do
    owner = Keyword.fetch!(options, :owner)
    deadline = Keyword.fetch!(options, :deadline_ms)
    token = make_ref()

    %{
      owner: owner,
      attempt_id: Keyword.fetch!(options, :attempt_id),
      deadline_ms: deadline,
      token: token,
      monitor: Process.monitor(owner),
      failed?: false,
      timer: Process.send_after(self(), {:mixer_policy_expired, token}, max(deadline - now(), 0))
    }
  end

  defp cleanup(pending) do
    release_lease(pending)
    PreparedSubscriptions.cleanup(pending.subscriptions)
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
    subscriptions = Keyword.get(options, :subscriptions, [])

    if is_pid(owner) and is_binary(attempt) and byte_size(attempt) in 1..128 and
         is_integer(deadline) and deadline > now() and is_list(subscriptions) and
         length(subscriptions) <= 255 and Enum.all?(subscriptions, &Keyword.keyword?/1),
       do: :ok,
       else: {:error, :invalid_preparation}
  end

  defp alias_resource(resource, token), do: %{resource | binding: {:prepared_policy, token}}
  defp remaining(options), do: min(max(Keyword.fetch!(options, :deadline_ms) - now(), 1), 5_000)
  defp now, do: System.monotonic_time(:millisecond)
end
