defmodule Vxpipe.CallEngine.RoomAuthority.StartupReadiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.{CallLifecycle, Error, ResolvedCallPlan}

  alias Vxpipe.CallEngine.RoomAuthority.{
    CallerIdle,
    ConnectionLifecycle,
    FirstMessage,
    OpeningAudio,
    ReadinessBinding,
    Startup,
    StartupProbe
  }

  alias Vxpipe.CallEngine.{Id, RoomCapabilitySupervisor, RoomMixer}
  alias Vxpipe.CallEngine.Media.OutputSink
  alias Vxpipe.CallEngine.WaitSounds.Player

  def preparation_result(ref, result, state) do
    Process.demonitor(ref, [:flush])

    with {:ok, prepared} <- result,
         {:ok, state} <- Startup.install(prepared, state),
         {:ok, state} <- prepared(state) do
      {:noreply, CallerIdle.reconcile(state)}
    else
      _failed ->
        failed(state, :startup_unavailable)
        ConnectionLifecycle.notify(state.connections, :call_start_failed)
        {:stop, :startup_unavailable, state}
    end
  end

  def opening_preparation_result(ref, result, state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, voice} ->
        state = %{
          state
          | opening_audio: %{
              state.opening_audio
              | capability: Startup.activate_text_to_speech(voice)
            },
            startup: %{state.startup | opening_task: nil}
        }

        reply(reconcile(state), state)

      _failed ->
        failed(state, :opening_audio_unavailable)
        {:stop, :opening_audio_unavailable, state}
    end
  end

  def reply({:ok, state}, _previous), do: {:noreply, CallerIdle.reconcile(state)}

  def reply({:error, %Error{code: code}}, state) do
    failed(state, code)
    ConnectionLifecycle.notify(state.connections, :call_start_failed)
    {:stop, code, state}
  end

  def reply({:error, _reason}, state) do
    failed(state, :startup_unavailable)
    ConnectionLifecycle.notify(state.connections, :call_start_failed)
    {:stop, :startup_unavailable, state}
  end

  def failed(%{startup_ready?: false, call_lifecycle: lifecycle} = state, reason)
      when is_pid(lifecycle),
      do: CallLifecycle.startup_failed(state.snapshot.incarnation_id, reason)

  def failed(_state, _reason), do: :ok

  def capability_failed(%{startup: startup} = state, reason) when startup != nil do
    cancel_probe(startup.readiness, state)
    cancel_probe(startup.release_task, state)

    startup = %{
      startup
      | readiness: nil,
        release_task: nil,
        ready_graph: nil,
        resources_ready?: false
    }

    state = %{state | startup: startup}
    _ = failed(state, reason)
    state
  end

  def bind(%CreateRoom{}, _incarnation_id), do: {:ok, nil}

  def bind(%ResolvedCallPlan{}, incarnation_id) do
    case CallLifecycle.bind(incarnation_id, self()) do
      {:ok, lifecycle} -> {:ok, lifecycle}
      {:error, :unavailable} -> {:error, :call_lifecycle_unavailable}
    end
  end

  def connection_attached(command, %{startup: startup, startup_ready?: false} = state)
      when startup != nil do
    connection = Map.fetch!(state.connections, command.connection_id)
    state = start_output_probe(command, connection, state)
    ready(state)
  end

  def connection_attached(command, state) do
    if Map.get(state.speech_to_text_runtime, command.participant_id) == nil do
      ready(state)
    else
      {:ok, state}
    end
  end

  def prepared(state) do
    Enum.each(state.connections, fn {_id, connection} ->
      if connection.speech_to_text == nil and
           Map.get(state.speech_to_text_runtime, connection.participant_id) != nil do
        send(connection.pid, {:vxpipe_startup_speech, connection.room_monitor})
      end
    end)

    ready(state)
  end

  def ready(%{startup: %{status: :preparing}} = state), do: {:ok, state}

  def ready(%{startup: startup, startup_ready?: false} = state) when startup != nil do
    blockers =
      cond do
        map_size(state.connections) == 0 -> [:media]
        pending_speech?(state) -> [:speech_to_text]
        true -> []
      end

    _ = CallLifecycle.startup_progress(state.call_lifecycle, :connections, blockers)
    state = start_room_probe(state)
    reconcile(state)
  end

  def ready(%{startup_ready?: true} = state), do: FirstMessage.start(state)

  def ready(state) do
    case CallLifecycle.ready(state.call_lifecycle) do
      :ok -> FirstMessage.start(%{state | startup_ready?: true})
      {:error, :unavailable} -> {:error, lifecycle_unavailable()}
    end
  end

  def output_result(reference, connection_id, result, state) do
    case Map.get(state.startup.waits, connection_id) do
      %{task: %Task{ref: ^reference}} = wait ->
        Process.demonitor(reference, [:flush])

        if result == :ok do
          wait = %{wait | task: nil, status: :ready}
          state = put_wait(state, connection_id, wait)
          reconcile(state)
        else
          {:error, startup_unavailable()}
        end

      _stale ->
        {:ok, state}
    end
  end

  def room_result(reference, result, %{startup: %{readiness: %Task{ref: reference}}} = state) do
    Process.demonitor(reference, [:flush])

    case result do
      {:ok, graph} ->
        _ = CallLifecycle.startup_progress(state.call_lifecycle, :release, [])
        startup = %{state.startup | readiness: nil, resources_ready?: true, ready_graph: graph}
        reconcile(%{state | startup: startup})

      _failed ->
        {:error, startup_unavailable()}
    end
  end

  def room_result(_reference, _result, state), do: {:ok, state}

  def release_result(
        reference,
        result,
        %{startup: %{release_task: %Task{ref: reference}}} = state
      ) do
    Process.demonitor(reference, [:flush])
    state = %{state | startup: %{state.startup | release_task: nil}}

    cond do
      result == :ok and current_graph?(state) ->
        waits =
          Map.new(state.startup.waits, fn {id, wait} ->
            discard_wait(wait, state)
            {id, %{wait | player: nil, monitor: nil, status: :stopped}}
          end)

        complete(%{state | startup: %{state.startup | waits: waits}})

      result in [{:error, :readiness_failed}, {:error, :deadline_elapsed}] ->
        {:error, startup_unavailable()}

      true ->
        startup = %{state.startup | resources_ready?: false, ready_graph: nil}
        ready(%{state | startup: startup})
    end
  end

  def release_result(_reference, _result, state), do: {:ok, state}

  defp current_graph?(state) do
    graph = state.startup.ready_graph

    with {:ok, binding} <- ReadinessBinding.capture(state),
         true <- binding == graph.inventory.binding,
         :ok <-
           Vxpipe.CallEngine.MediaPolicy.Authority.validate_candidate(
             state.media_policy_authority,
             graph.inventory.candidate,
             1_000
           ) do
      true
    else
      _stale -> false
    end
  end

  def playback(player, episode, status, state) do
    case Enum.find(state.startup.waits, fn {_id, wait} ->
           wait.player == player and wait.episode == episode
         end) do
      {id, wait} ->
        case status do
          :stopped ->
            Process.demonitor(wait.monitor, [:flush])
            reconcile(put_wait(state, id, %{wait | player: nil, monitor: nil, status: :stopped}))

          {:paused, _offset} ->
            reconcile(put_wait(state, id, %{wait | status: :paused}))

          {:failed, _reason} ->
            {:error, startup_unavailable()}
        end

      nil ->
        {:ok, state}
    end
  end

  def opening_changed(%{startup: nil} = state), do: FirstMessage.start(state)
  def opening_changed(state), do: reconcile(state)

  def connection_removed(_id, _connection, %{startup: nil} = state), do: state
  def connection_removed(_id, _connection, %{startup_ready?: true} = state), do: state

  def connection_removed(id, connection, state) do
    {wait, waits} = Map.pop(state.startup.waits, id)
    discard_wait(wait, state)

    if connection != nil and is_pid(connection.output_sink),
      do: OutputSink.clear(connection.output_sink)

    cancel_probe(state.startup.readiness, state)
    cancel_probe(state.startup.release_task, state)
    _ = CallLifecycle.startup_progress(state.call_lifecycle, :release, [])

    startup = %{
      state.startup
      | waits: waits,
        readiness: nil,
        release_task: nil,
        ready_graph: nil,
        resources_ready?: false
    }

    state = %{state | startup: startup}
    plan = state.participant_transfer_runtime.plan
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    if connection != nil and connection.participant_id == caller.participant_id and
         not Enum.any?(state.connections, fn {_id, remaining} ->
           remaining.participant_id == caller.participant_id
         end) do
      CallLifecycle.startup_failed(state.snapshot.incarnation_id, :caller_disconnected)
    end

    if state.startup.status == :prepared, do: start_room_probe(state), else: state
  end

  def player_down?(monitor, %{startup: startup}) when startup != nil do
    Enum.any?(startup.waits, fn {_id, wait} -> wait.monitor == monitor end)
  end

  def player_down?(_monitor, _state), do: false

  defp discard_wait(nil, _state), do: :ok

  defp discard_wait(wait, state) do
    cancel_probe(wait.task, state)
    if wait.monitor, do: Process.demonitor(wait.monitor, [:flush])

    if wait.player,
      do: RoomCapabilitySupervisor.stop_capability(state.snapshot.incarnation_id, wait.player)
  end

  defp cancel_probe(nil, _state), do: :ok

  defp cancel_probe(task, state) do
    Task.shutdown(task, :brutal_kill)
    CallLifecycle.startup_progress(state.call_lifecycle, task.pid, [])
  end

  defp start_output_probe(_command, %{output_sink: nil}, state), do: state

  defp start_output_probe(command, connection, state) do
    identity =
      Map.take(command, [:tenant_id, :room_id, :incarnation_id, :participant_id, :connection_id])

    authority = state.media_policy_authority
    deadline = state.startup.deadline_ms

    task =
      Task.Supervisor.async(Vxpipe.CallEngine.ReadinessTaskSupervisor, fn ->
        {:startup_output, command.connection_id,
         StartupProbe.output(connection.pid, identity, authority, deadline)}
      end)

    put_wait(state, command.connection_id, %{
      task: task,
      player: nil,
      monitor: nil,
      episode: Id.generate(:command),
      status: :checking
    })
  end

  defp start_room_probe(%{startup: %{readiness: nil, resources_ready?: false}} = state)
       when map_size(state.connections) > 0 do
    if pending_speech?(state) do
      state
    else
      room = self()
      authority = state.media_policy_authority
      incarnation = state.snapshot.incarnation_id
      deadline = state.startup.deadline_ms

      task =
        Task.Supervisor.async(Vxpipe.CallEngine.ReadinessTaskSupervisor, fn ->
          {:startup_ready, StartupProbe.room(room, authority, incarnation, deadline)}
        end)

      %{state | startup: %{state.startup | readiness: task}}
    end
  end

  defp start_room_probe(state), do: state

  defp pending_speech?(state) do
    Enum.any?(state.connections, fn {_id, connection} ->
      connection.role == :human and connection.admission == :main and
        connection.speech_to_text == nil and
        Map.get(state.speech_to_text_runtime, connection.participant_id) != nil
    end)
  end

  defp reconcile(%{startup_ready?: true} = state), do: FirstMessage.start(state)

  defp reconcile(state) do
    blockers = if state.opening_audio.phase == :open, do: [], else: [:opening_audio]
    _ = CallLifecycle.startup_progress(state.call_lifecycle, :opening_audio, blockers)

    with {:ok, state} <- update_waits(state),
         {:ok, state} <- start_opening(state) do
      verify_release(state)
    end
  end

  defp update_waits(state) do
    Enum.reduce_while(state.startup.waits, {:ok, state}, fn {id, wait}, {:ok, state} ->
      case update_wait(id, wait, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        error -> {:halt, error}
      end
    end)
  end

  defp update_wait(id, %{status: status} = wait, state) when status in [:ready, :stopped] do
    if (state.startup.resources_ready? and state.opening_audio.phase == :open) or
         state.opening_audio.phase in [:ready, :playing] do
      {:ok, put_wait(state, id, %{wait | status: :stopped})}
    else
      start_wait(id, wait, state)
    end
  end

  defp update_wait(id, %{status: status} = wait, state) when status in [:playing, :paused] do
    cond do
      state.startup.resources_ready? and state.opening_audio.phase == :open and status == :playing ->
        Player.pause(wait.player)
        {:ok, put_wait(state, id, %{wait | status: :pausing})}

      state.opening_audio.phase == :ready and status == :playing ->
        Player.pause(wait.player)
        {:ok, put_wait(state, id, %{wait | status: :pausing})}

      not state.startup.resources_ready? and state.opening_audio.phase == :open and
          status == :paused ->
        Player.resume(wait.player)
        {:ok, put_wait(state, id, %{wait | status: :playing})}

      true ->
        {:ok, state}
    end
  end

  defp update_wait(_id, _wait, state), do: {:ok, state}

  defp start_wait(id, wait, state) do
    plan = state.participant_transfer_runtime.plan
    assets = plan.wait_sound_assets
    connection = Map.fetch!(state.connections, id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    digest =
      if connection.participant_id == caller.participant_id,
        do: Map.fetch!(assets.slots, :call_setup)

    if digest do
      options = [
        owner: self(),
        episode_id: wait.episode,
        tenant_id: plan.tenant_id,
        room_id: plan.room_id,
        participant_id: connection.participant_id,
        connection_generation: id,
        attempt_id: "call-setup",
        phase: :call_setup,
        sinks: %{id => connection.output_sink},
        asset: Map.fetch!(assets.assets, digest)
      ]

      case RoomCapabilitySupervisor.start_wait_audio(state.snapshot.incarnation_id, options) do
        {:ok, player} ->
          {:ok,
           put_wait(state, id, %{
             wait
             | player: player,
               monitor: Process.monitor(player),
               status: :playing
           })}

        _failed ->
          {:error, startup_unavailable()}
      end
    else
      {:ok, put_wait(state, id, %{wait | status: :stopped})}
    end
  end

  defp start_opening(%{opening_audio: %{phase: phase}} = state)
       when phase not in [:awaiting_connection, :ready], do: {:ok, state}

  defp start_opening(state) do
    target = state.opening_audio.target_participant_id

    case Enum.find(state.connections, fn {id, connection} ->
           connection.participant_id == target and
             match?(
               %{status: status} when status != :checking,
               Map.get(state.startup.waits, id)
             )
         end) do
      {_id, connection} ->
        begin_or_release_opening(connection, state)

      nil ->
        {:ok, state}
    end
  end

  defp begin_or_release_opening(connection, %{opening_audio: %{phase: :ready}} = state) do
    wait = Map.fetch!(state.startup.waits, connection.attach_command.connection_id)

    if wait.status in [:paused, :stopped] do
      with {:ok, _discarded} <- OutputSink.clear(connection.output_sink),
           {:ok, opening} <- OpeningAudio.release(state.opening_audio) do
        {:ok, %{state | opening_audio: opening}}
      else
        _failed -> {:error, startup_unavailable()}
      end
    else
      {:ok, state}
    end
  end

  defp begin_or_release_opening(connection, state) do
    with {:ok, opening} <-
           OpeningAudio.start(
             state.opening_audio,
             connection.attach_command,
             connection,
             state.snapshot,
             self()
           ) do
      {:ok, %{state | opening_audio: opening}}
    end
  end

  defp verify_release(
         %{startup: %{resources_ready?: true, release_task: nil}, opening_audio: %{phase: :open}} =
           state
       ) do
    if Enum.all?(state.startup.waits, fn {_id, wait} -> wait.status in [:paused, :stopped] end) do
      with :ok <- clear_outputs(state) do
        room = self()
        graph = state.startup.ready_graph
        deadline = state.startup.deadline_ms

        task =
          Task.Supervisor.async(Vxpipe.CallEngine.ReadinessTaskSupervisor, fn ->
            {:startup_release, StartupProbe.verify(room, graph, deadline)}
          end)

        {:ok, %{state | startup: %{state.startup | release_task: task}}}
      end
    else
      {:ok, state}
    end
  end

  defp verify_release(state), do: {:ok, state}

  defp complete(%{startup: %{resources_ready?: true}, opening_audio: %{phase: :open}} = state) do
    if Enum.all?(state.startup.waits, fn {_id, wait} -> wait.status == :stopped end) do
      with :ok <- CallLifecycle.ready(state.call_lifecycle),
           :ok <- RoomMixer.complete_opening(state.room_mixer) do
        state = ConnectionLifecycle.open_inputs(%{state | startup_ready?: true})

        Enum.each(state.connections, fn {_id, connection} ->
          send(connection.pid, {:vxpipe_call_ready, connection.room_monitor})
        end)

        FirstMessage.start(state)
      else
        _failed -> {:error, startup_unavailable()}
      end
    else
      {:ok, state}
    end
  end

  defp complete(state), do: {:ok, state}

  defp clear_outputs(state) do
    Enum.reduce_while(state.startup.waits, :ok, fn {id, _wait}, :ok ->
      case OutputSink.clear(Map.fetch!(state.connections, id).output_sink) do
        {:ok, _discarded} -> {:cont, :ok}
        _failed -> {:halt, {:error, :output_unavailable}}
      end
    end)
  end

  defp put_wait(state, id, wait),
    do: %{state | startup: %{state.startup | waits: Map.put(state.startup.waits, id, wait)}}

  defp startup_unavailable,
    do: Error.new(:startup_unavailable, "The call could not become ready.", retryable: true)

  defp lifecycle_unavailable do
    Error.new(
      :call_lifecycle_unavailable,
      "The call lifecycle could not be updated.",
      retryable: true
    )
  end
end
