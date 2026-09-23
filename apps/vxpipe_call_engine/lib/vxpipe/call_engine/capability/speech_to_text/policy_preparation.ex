defmodule Vxpipe.CallEngine.Capability.SpeechToText.PolicyPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToText.{State, Usage}

  alias Vxpipe.CallEngine.MediaPolicy.{
    Authority,
    Candidate,
    Effective,
    Intervals,
    Snapshot,
    SpeechToTextDemand
  }

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.Telemetry

  @derive {Inspect, only: [:attempt_id, :change, :deadline_ms]}
  @enforce_keys [
    :candidate,
    :attempt_id,
    :owner,
    :monitor,
    :deadline_ms,
    :timer,
    :token,
    :change,
    :state
  ]
  defstruct @enforce_keys ++ [failed?: false]

  def request(capability, %Candidate{} = candidate, options) do
    with :ok <- validate_options(options),
         :ok <- Authority.validate_candidate(candidate.authority, candidate, remaining(options)),
         do: GenServer.call(capability, {:prepare_policy, candidate, options}, remaining(options))
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def begin(state, candidate, options) do
    with :ok <- validate_options(options),
         :ok <- validate_authority(state, candidate),
         true <- candidate.base_snapshot == state.policy do
      begin_current(state, candidate, options)
    else
      false -> {:error, :stale_candidate}
      {:error, _reason} = error -> error
    end
  end

  defp validate_authority(state, candidate) do
    if Authority.whereis(state.identity.incarnation_id) == candidate.authority,
      do: :ok,
      else: {:error, :wrong_policy_authority}
  end

  defp begin_current(%{pending_policy: nil} = state, candidate, options) do
    change = change(state, candidate.snapshot)

    with {:ok, session} <- prepare_session(state, candidate.snapshot, change, options) do
      token = make_ref()
      owner = Keyword.fetch!(options, :owner)
      deadline = Keyword.fetch!(options, :deadline_ms)

      pending = %__MODULE__{
        candidate: candidate,
        attempt_id: Keyword.fetch!(options, :attempt_id),
        owner: owner,
        monitor: Process.monitor(owner),
        deadline_ms: deadline,
        timer: Process.send_after(self(), {:stt_policy_expired, token}, max(deadline - now(), 0)),
        token: token,
        change: change,
        state: session
      }

      state = %{state | pending_policy: pending}
      {:ok, reply(state), state}
    end
  end

  defp begin_current(state, candidate, options) do
    pending = state.pending_policy

    if pending.attempt_id == Keyword.fetch!(options, :attempt_id) and
         pending.owner == Keyword.fetch!(options, :owner) and
         pending.deadline_ms == Keyword.fetch!(options, :deadline_ms) and not pending.failed? and
         pending.change == change(state, candidate.snapshot) and
         Intervals.unchanged?(
           pending.candidate.snapshot,
           candidate.snapshot,
           :speech_to_text,
           state.identity.participant_id
         ) do
      session =
        if pending.state do
          %{
            pending.state
            | policy: candidate.snapshot,
              policy_revision:
                Snapshot.interval(
                  candidate.snapshot,
                  :speech_to_text,
                  state.identity.participant_id
                )
          }
        end

      state = %{state | pending_policy: %{pending | candidate: candidate, state: session}}
      {:ok, reply(state), state}
    else
      {:error, :preparation_conflict}
    end
  end

  def discard(%{pending_policy: %{token: token}} = state, token) do
    cleanup(state.pending_policy)
    {:ok, %{state | pending_policy: nil}}
  end

  def discard(_state, _token), do: {:error, :stale_preparation}

  def readiness(%{pending_policy: %{token: token} = pending} = state, token) do
    if now() < pending.deadline_ms and pending.candidate.base_snapshot == state.policy do
      case resources(state) do
        [{resource, status}] -> {:ok, resource, status}
        _not_required -> {:error, :unavailable}
      end
    else
      {:error, :unavailable}
    end
  end

  def readiness(%{adopted_policy_token: token} = state, token) when is_reference(token) do
    {:ok, resource, status} = State.readiness(state)
    resource = %{resource | binding: {resource.binding, :prepared_policy, token}}
    {:ok, resource, status}
  end

  def readiness(_state, _token), do: {:error, :unavailable}

  def input_binding(state, %Resource{binding: {_connection, :prepared_policy, token}} = expected) do
    with {:ok, ^expected, status} <- readiness(state, token) do
      {session, intervals} = input_session(state, token)
      {:ok, binding} = State.input_binding(session)
      {:ok, %{binding | resource: expected, status: status, policy_intervals: intervals}}
    else
      _stale_or_changed -> {:error, :unavailable}
    end
  end

  def input_binding(state, %Resource{} = expected) do
    case State.input_binding(state) do
      {:ok, %{resource: ^expected}} = binding -> binding
      _stale_or_changed -> {:error, :unavailable}
    end
  end

  def input_binding(_state, _expected), do: {:error, :unavailable}

  defp input_session(%{pending_policy: %{token: token} = pending} = state, token) do
    {pending.state, Enum.uniq([state.policy_revision, pending.state.policy_revision])}
  end

  defp input_session(state, _adopted_token), do: {state, [state.policy_revision]}

  def install(%{pending_policy: nil} = state, snapshot), do: install_live(state, snapshot)

  def install(state, snapshot) do
    with {:ok, normalized} <- Snapshot.prepare(snapshot, state.policy) do
      if normalized == state.pending_policy.candidate.snapshot do
        commit(state, normalized)
      else
        state = invalidate_if_affected(state, normalized)
        install_live(state, snapshot)
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp invalidate_if_affected(state, snapshot) do
    if Intervals.unchanged?(
         state.policy,
         snapshot,
         :speech_to_text,
         state.identity.participant_id
       ) and activity_authority_unchanged?(state, snapshot) do
      state
    else
      {:ok, state} = discard(state, state.pending_policy.token)
      state
    end
  end

  defp activity_authority_unchanged?(%{activity_agent_id: nil}, _snapshot), do: true
  defp activity_authority_unchanged?(%{policy: nil}, _snapshot), do: false

  defp activity_authority_unchanged?(state, snapshot) do
    source = state.identity.participant_id
    agent = state.activity_agent_id
    activity_authority(state.policy, source, agent) == activity_authority(snapshot, source, agent)
  end

  defp activity_authority(snapshot, source, agent) do
    {
      MapSet.member?(snapshot.present_participant_ids, agent),
      Effective.audio_route_permitted?(snapshot.effective, source, agent),
      Effective.audio_route_permitted?(snapshot.effective, agent, source)
    }
  end

  def prepared(%{pending_policy: %{state: session} = pending} = state, allocation, descriptor) do
    case State.prepared(session, allocation, descriptor) do
      {:ok, session} -> {:ok, %{state | pending_policy: %{pending | state: session}}}
      {:error, _reason} = error -> error
    end
  end

  def prepared(_state, _allocation, _descriptor), do: {:error, :stale_session}

  def fail(state, reason \\ :cancelled) do
    pending = state.pending_policy
    failed? = reason in [:provider_failed, :invalid_provider_message]
    cleanup(pending, if(failed?, do: :failed, else: :cancelled))

    if failed? and pending.state != nil and not pending.failed?,
      do: Telemetry.provider_failure(:stt, pending.state.provider_module, reason)

    session =
      if pending.state do
        %{pending.state | session: nil, usage: nil, readiness_status: :failed}
      end

    %{state | pending_policy: %{pending | state: session, failed?: true}}
  end

  def close(%{pending_policy: nil}), do: :ok
  def close(state), do: cleanup(state.pending_policy)

  defp commit(state, snapshot) do
    pending = state.pending_policy

    cond do
      pending.failed? or now() >= pending.deadline_ms ->
        {:error, :policy_not_ready, state}

      pending.change == :replace ->
        commit_replacement(state)

      true ->
        release_lease(pending)
        install_live(%{state | pending_policy: nil}, snapshot)
    end
  end

  defp commit_replacement(state) do
    pending = state.pending_policy

    case State.readiness(pending.state) do
      {:ok, _resource, :ready} ->
        with {:ok, adopted} <- State.adopt_prepared(pending.state, pending.deadline_ms) do
          commit_adopted_replacement(state, pending, adopted)
        else
          {:error, _reason} -> {:error, :policy_not_ready, state}
        end

      _not_ready ->
        {:error, :policy_not_ready, state}
    end
  end

  defp commit_adopted_replacement(state, pending, adopted) do
    if handoff_valid?(pending) do
      case State.retire_active(state, pending.deadline_ms) do
        {:ok, retired} -> finish_adopted_replacement(retired, pending, adopted)
        {:error, _reason} -> reject_adopted_replacement(state, pending, adopted)
      end
    else
      reject_adopted_replacement(state, pending, adopted)
    end
  end

  defp finish_adopted_replacement(retired, pending, adopted) do
    if handoff_valid?(pending) do
      _finished = Usage.finish_session(retired, :cancelled)
      release_lease(pending)
      {:ok, %{adopted | adopted_policy_token: pending.token}}
    else
      _closed = adopted |> Usage.finish_session(:cancelled) |> State.close()
      failed = Usage.finish_session(retired, :failed)
      release_lease(pending)

      {:error, :policy_not_ready,
       %{
         failed
         | adopted_policy_token: nil,
           pending_policy: nil,
           readiness_status: :failed
       }}
    end
  end

  defp reject_adopted_replacement(state, pending, adopted) do
    _closed = adopted |> Usage.finish_session(:cancelled) |> State.close()
    release_lease(pending)
    {:error, :policy_not_ready, %{state | pending_policy: nil}}
  end

  defp install_live(state, snapshot) do
    case State.install_policy(state, snapshot) do
      {:ok, updated} -> {:ok, Usage.transition(state, updated)}
      {:error, reason, updated} -> {:error, reason, Usage.transition(state, updated)}
    end
  end

  defp reply(state) do
    pending = state.pending_policy

    %{
      token: pending.token,
      change: pending.change,
      resources: Enum.map(resources(state), &elem(&1, 0))
    }
  end

  defp resources(%{pending_policy: %{change: :replace} = pending}) do
    {:ok, resource, status} = State.readiness(pending.state)
    resource = %{resource | binding: {resource.binding, :prepared_policy, pending.token}}
    [{resource, status}]
  end

  defp resources(state) do
    if demanded?(state, state.pending_policy.candidate.snapshot) do
      {:ok, resource, status} = State.readiness(state)
      [{resource, status}]
    else
      []
    end
  end

  defp change(state, snapshot) do
    cond do
      state.policy_revision ==
        Snapshot.interval(snapshot, :speech_to_text, state.identity.participant_id) and
          current_demand?(state) == demanded?(state, snapshot) ->
        :retain

      demanded?(state, snapshot) ->
        :replace

      true ->
        :disable
    end
  end

  defp current_demand?(%{policy: nil}), do: false
  defp current_demand?(state), do: demanded?(state, state.policy)

  defp demanded?(state, snapshot) do
    SpeechToTextDemand.required?(
      snapshot,
      state.identity.participant_id,
      state.activity_agent_id
    )
  end

  defp prepare_session(state, snapshot, :replace, options),
    do: State.prepare_session(state, snapshot, Keyword.fetch!(options, :deadline_ms))

  defp prepare_session(_state, _snapshot, _change, _options), do: {:ok, nil}

  defp cleanup(pending, outcome \\ :cancelled) do
    release_lease(pending)
    if pending.state, do: pending.state |> Usage.finish_session(outcome) |> State.close()
    :ok
  end

  defp release_lease(pending) do
    Process.cancel_timer(pending.timer)
    Process.demonitor(pending.monitor, [:flush])
    :ok
  end

  defp handoff_valid?(pending),
    do: Process.alive?(pending.owner) and now() < pending.deadline_ms

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
