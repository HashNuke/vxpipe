defmodule Vxpipe.CallEngine.RoomRecording.PolicyPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Candidate, Snapshot}
  alias Vxpipe.CallEngine.{RoomMixer, RoomRecording}
  alias Vxpipe.CallEngine.RoomRecording.{Preparation, PreparedTracks, Readiness}

  def request(recording, %Candidate{} = candidate, tracks, options) do
    with :ok <- validate(options),
         :ok <- Authority.validate_candidate(candidate.authority, candidate, remaining(options)),
         {:ok, config} <-
           GenServer.call(recording, :preparation_configuration, remaining(options)),
         true <- Authority.whereis(config.identity.incarnation_id) == candidate.authority,
         :ok <- register(recording, candidate.authority, remaining(options)),
         {:ok, mixer} <- RoomMixer.prepare_policy(config.mixer, candidate, options),
         {:ok, token} <-
           GenServer.call(
             recording,
             {:prepare_policy, candidate, tracks, mixer.recording_subscriptions, options},
             remaining(options)
           ) do
      case Readiness.prepared_resources(recording, token) do
        {:ok, resources} ->
          {:ok, %{token: token, resources: resources}}

        error ->
          _ = RoomRecording.discard_policy(recording, token)
          error
      end
    else
      false -> {:error, :wrong_room}
      {:error, _reason} = error -> error
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp register(recording, authority, timeout) do
    case Authority.register_enforcer(authority, recording, timeout) do
      {:ok, _snapshot} -> :ok
      {:error, :already_registered} -> :ok
      error -> error
    end
  end

  def begin(state, candidate, tracks, subscriptions, options) do
    policy = %{present: candidate.snapshot.present_participant_ids, format: state.format}

    with :ok <- validate(options),
         true <- candidate.base_snapshot == state.policy,
         true <- candidate.snapshot.effective.record_audio or tracks == [],
         state = retire_failed_lease(state, options),
         :ok <- compatible(state.pending_policy, options),
         :ok <- Preparation.validate_tracks(tracks, state.configuration, policy),
         true <- valid_subscriptions?(state, subscriptions),
         previous = if(state.pending_policy, do: state.pending_policy.outputs, else: %{}),
         {:ok, selections, outputs} <-
           PreparedTracks.stage(
             state,
             tracks,
             previous,
             options,
             candidate.snapshot.effective.record_audio
           ) do
      pending = state.pending_policy || lease(options)
      release_monitors(pending)

      monitors =
        Map.new(outputs, fn {_key, %{lease: lease}} ->
          {Process.monitor(lease.source), lease.source}
        end)

      pending =
        Map.merge(pending, %{
          candidate: candidate,
          selections: selections,
          outputs: outputs,
          subscriptions: Map.take(subscriptions, Map.keys(state.streams)),
          ready?: false,
          monitors: monitors,
          cached: nil
        })

      {:ok, pending.token, %{state | pending_policy: pending}}
    else
      false -> {:error, :stale_recording_policy}
      {:error, _reason} = error -> error
    end
  end

  def binding(state, token) do
    case state.pending_policy do
      %{token: ^token} = pending ->
        cond do
          pending.failed? or pending.deadline <= now() ->
            {:error, :unavailable}

          pending.candidate.base_snapshot != state.policy ->
            {:error, :unavailable}

          not PreparedTracks.consistent?(state, pending) ->
            {:error, :unavailable}

          true ->
            streams = PreparedTracks.streams(state, pending)
            desired_interval = Snapshot.interval(pending.candidate.snapshot, :recording)

            binding =
              Readiness.binding(%{state | streams: streams, prepared_interval: desired_interval})

            same? =
              same_bindings?(binding, Readiness.binding(state)) and
                desired_interval == Snapshot.interval(state.policy, :recording)

            resource =
              if same?,
                do: state.readiness_resource,
                else: %{
                  state.readiness_resource
                  | binding:
                      {state.configuration.identity.incarnation_id, :prepared_policy, token}
                }

            {:ok, binding |> Map.put(:resource, resource) |> Map.put(:preparation_token, token)}
        end

      _other ->
        case state.readiness_resource.binding do
          {_id, :prepared_policy, ^token} -> {:ok, current_binding(state)}
          _stale -> {:error, :unavailable}
        end
    end
  end

  def current_binding(state) do
    current = Readiness.binding(state)

    if state.pending_policy do
      case binding(state, state.pending_policy.token) do
        {:ok, pending} ->
          if same_bindings?(pending, current), do: pending, else: current

        _unavailable ->
          current
      end
    else
      current
    end
  end

  defp same_bindings?(first, second) do
    keys = [:resource, :writer, :handles, :selections, :subscriptions]
    Map.take(first, keys) == Map.take(second, keys)
  end

  def confirm(state, token, expected, resource, status, dependencies) do
    case binding(state, token) do
      {:ok, ^expected} ->
        monitors = monitor_writers(state.pending_policy.monitors, dependencies)

        pending = %{
          state.pending_policy
          | ready?: status == :ready,
            cached: resource,
            monitors: monitors
        }

        {:ok, %{state | pending_policy: pending}}

      _changed ->
        {:error, :unavailable}
    end
  end

  defp monitor_writers(monitors, dependencies) do
    observed = MapSet.new(Map.values(monitors))

    writers =
      for %{kind: :recording_writer, instance: writer} <- dependencies,
          writer != self(),
          into: MapSet.new(),
          do: writer

    Enum.reduce(MapSet.difference(writers, observed), monitors, fn writer, monitors ->
      Map.put(monitors, Process.monitor(writer), writer)
    end)
  end

  def install(%{pending_policy: nil} = state, _snapshot), do: {:ok, state}

  def install(state, snapshot) do
    pending = state.pending_policy

    cond do
      pending.candidate.snapshot != snapshot ->
        {:ok, state}

      not pending.ready? or pending.failed? or pending.deadline <= now() or
          pending.candidate.base_snapshot != state.policy ->
        {:error, :policy_not_ready}

      not PreparedTracks.consistent?(state, pending) ->
        {:error, :policy_not_ready}

      true ->
        case PreparedTracks.adopt(pending.outputs) do
          :ok ->
            streams = PreparedTracks.streams(state, pending)
            resource = %{state.readiness_resource | binding: pending.cached.binding}
            release(pending)

            {:ok,
             %{
               state
               | streams: streams,
                 pending_policy: nil,
                 prepared_interval: Snapshot.interval(snapshot, :recording),
                 readiness_resource: resource
             }}

          error ->
            error
        end
    end
  end

  def discard(%{pending_policy: %{token: token} = pending} = state, token) do
    release(pending)
    PreparedTracks.close(pending.outputs)
    {:ok, %{state | pending_policy: nil}}
  end

  def discard(_state, _token), do: {:error, :stale_preparation}

  def fail(%{pending_policy: %{failed?: false} = pending} = state) do
    release(pending)
    PreparedTracks.close(pending.outputs)
    send(pending.owner, {:vxpipe_recording_policy_failed, self(), pending.token})
    %{state | pending_policy: %{pending | failed?: true, ready?: false}}
  end

  def fail(state), do: state

  defp valid_subscriptions?(state, subscriptions) do
    Enum.all?(state.streams, fn {id, stream} ->
      case Map.get(subscriptions, id) do
        %{mixer: mixer, token: token, purpose: :recording} ->
          mixer == state.configuration.mixer and token == stream.subscription.token

        _missing ->
          false
      end
    end)
  end

  defp lease(options) do
    token = make_ref()
    deadline = Keyword.fetch!(options, :deadline_ms)
    owner = Keyword.fetch!(options, :owner)

    %{
      token: token,
      owner: owner,
      attempt: Keyword.fetch!(options, :attempt_id),
      deadline: deadline,
      monitor: Process.monitor(owner),
      timer:
        Process.send_after(self(), {:recording_policy_expired, token}, max(deadline - now(), 0)),
      monitors: %{},
      failed?: false
    }
  end

  defp retire_failed_lease(%{pending_policy: %{failed?: true, owner: owner}} = state, options) do
    if owner == Keyword.fetch!(options, :owner), do: state, else: %{state | pending_policy: nil}
  end

  defp retire_failed_lease(state, _options), do: state

  defp compatible(nil, _options), do: :ok

  defp compatible(pending, options) do
    if not pending.failed? and pending.owner == Keyword.fetch!(options, :owner) and
         pending.attempt == Keyword.fetch!(options, :attempt_id) and
         pending.deadline == Keyword.fetch!(options, :deadline_ms),
       do: :ok,
       else: {:error, :preparation_conflict}
  end

  defp release(pending) do
    Process.cancel_timer(pending.timer)
    Process.demonitor(pending.monitor, [:flush])
    release_monitors(pending)
  end

  defp release_monitors(pending),
    do:
      Enum.each(pending.monitors, fn {monitor, _pid} -> Process.demonitor(monitor, [:flush]) end)

  defp validate(options) do
    deadline = Keyword.get(options, :deadline_ms)
    attempt = Keyword.get(options, :attempt_id)

    if is_pid(Keyword.get(options, :owner)) and is_integer(deadline) and deadline > now() and
         is_binary(attempt) and byte_size(attempt) in 1..128,
       do: :ok,
       else: {:error, :invalid_preparation}
  end

  defp remaining(options) do
    remaining = Keyword.fetch!(options, :deadline_ms) - now()
    if remaining > 0, do: remaining, else: exit(:deadline_elapsed)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
