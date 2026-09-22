defmodule Vxpipe.CallEngine.CallLoad.Runner do
  @moduledoc false
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.CallLoad.{Attribution, IngressObserver, Metrics, Room, Sink}
  alias Vxpipe.CallEngine.Media.STSIngress

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnInterrupted,
    AgentTurnFailed,
    ParticipantTurnStarted,
    ParticipantTranscription,
    TextOutput
  }

  alias Vxpipe.Providers.MorseCode.{STSSession, STTSession, TTSSession}

  @measurements [
    :admission_ms,
    :startup_ms,
    :input_acceptance_ms,
    :speech_onset_ms,
    :agent_speech_onset_ms,
    :first_audio_ms,
    :playback_ack_ms,
    :turn_completion_ms,
    :interruption_ms,
    :failure_isolation_ms,
    :cleanup_ms
  ]

  def configure(fixture, observer) do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(
        :fixture,
        {CallEngine.Diagnostics.AgentRuntimeModelProvider, [fixture: fixture]}
      )

    settings =
      original
      |> Keyword.put(:agent_runtime, runtime)
      |> Keyword.put(:speech_to_speech, providers: %{STSSession => [enabled: true]})
      |> Keyword.put(:text_to_speech,
        providers: %{TTSSession => [enabled: true, maximum_requests: 2]}
      )
      |> Keyword.put(:speech_to_text,
        providers: %{
          STTSession => [
            enabled: true,
            media_ingress: [
              owner: observer,
              maximum_frames: 25,
              maximum_bytes: 65_536,
              maximum_age_ms: 1_000,
              maximum_consecutive_overflows: 3
            ]
          ]
        }
      )

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    original
  end

  def restore(original),
    do: Application.put_env(:vxpipe_call_engine, CallEngine.Application, original)

  def run(mode, calls, supervisor, tasks, observer) do
    :ok = Metrics.validate(calls, 4, 90_000)
    coordinator = self()
    started = now()

    workers =
      Enum.map(1..calls, fn index ->
        Task.Supervisor.async_nolink(tasks, fn ->
          call(mode, index, supervisor, tasks, coordinator, observer)
        end)
      end)

    ready = barrier(:ready, calls)
    Enum.each(ready, &send(&1, :go))
    exercised = barrier(:exercised, calls)
    [victim | survivors] = exercised
    fault_at = now()
    send(victim, :fault)

    receive do
      {:faulted, ^victim} -> :ok
    after
      5_000 -> raise "fault containment timeout"
    end

    Enum.each(survivors, &send(&1, {:survive, fault_at}))
    results = Enum.map(workers, &Task.await(&1, 90_000))
    summarize(mode, calls, results, now() - started)
  end

  defp call(mode, index, supervisor, tasks, coordinator, observer) do
    plan = Room.plan(mode)

    try do
      context = Room.start(plan, mode, supervisor) |> Map.put(:ingress_observer, observer)
      state = initial(context, tasks)
      send(coordinator, {:ready, self()})

      receive do
        :go -> :ok
      after
        10_000 -> raise "start barrier timeout"
      end

      state = state |> begin_input(1) |> until(:ordinary)
      state = state |> begin_input(2) |> until(:barge)
      before_fault_drops = input_drops(context, state)
      send(coordinator, {:exercised, self()})

      state =
        receive do
          :fault ->
            cleanup_at = now()
            monitors = Enum.map(Room.members(context.root), &{&1, Process.monitor(&1)})
            Process.exit(context.authority, :kill)

            Enum.each(monitors, fn {pid, ref} ->
              receive do
                {:DOWN, ^ref, :process, ^pid, _} -> :ok
              after
                2_000 -> raise "fault leaked child"
              end
            end)

            send(coordinator, {:faulted, self()})
            state = measure(state, :cleanup_ms, now() - cleanup_at)
            %{state | cleaned: true, monitored_children: length(monitors)}

          {:survive, fault_at} ->
            result = state |> begin_input(4) |> until(:survive)
            result |> measure(:failure_isolation_ms, now() - fault_at) |> Map.put(:survived, true)
        after
          10_000 -> raise "failure barrier timeout"
        end

      stats = Sink.stats(context.sink)
      dropped = if state.cleaned, do: before_fault_drops, else: input_drops(context, state)
      cleanup_at = now()
      children = if state.cleaned, do: state.monitored_children, else: Room.stop(context.root)
      Room.stop_helpers(context, supervisor)
      state = if state.cleaned, do: state, else: measure(state, :cleanup_ms, now() - cleanup_at)

      %{
        samples: state.samples,
        completed: state.completed,
        interruptions: state.interruptions,
        survived: state.survived,
        cleaned: true,
        monitored_children: children,
        mailbox_peak: state.mailbox_peak,
        mailbox_growth: state.mailbox_peak - state.mailbox_initial,
        process_memory_peak_bytes: state.memory_peak,
        input_frames: state.input_frames,
        input_drops: dropped,
        sink: stats,
        caller_transcripts: state.caller_transcripts,
        agent_transcripts: state.agent_transcripts,
        errors: []
      }
    rescue
      error ->
        message = "call #{index}: #{Exception.message(error)}"
        send(coordinator, {:call_failed, message})
        %{errors: [message], cleaned: false}
    catch
      :exit, reason ->
        message = "call #{index} exited: #{inspect(reason)}"
        send(coordinator, {:call_failed, message})
        %{errors: [message], cleaned: false}
    after
      Room.cleanup(plan)
    end
  end

  defp initial(context, tasks) do
    {mailbox, memory} = sample(context)

    %{
      context: context,
      tasks: tasks,
      samples: Map.new(@measurements, &{&1, []}),
      completed: 0,
      interruptions: 0,
      survived: false,
      cleaned: false,
      monitored_children: 0,
      mailbox_initial: mailbox,
      mailbox_peak: mailbox,
      memory_peak: memory,
      input_frames: 0,
      input_rejections: 0,
      caller_transcripts: 0,
      agent_transcripts: 0,
      input_started: nil,
      barge_at: nil,
      turn: 0,
      attribution: Attribution.new(),
      input_finished: 0,
      deadline: now() + 90_000
    }
    |> measure(:admission_ms, context.admission_ms)
    |> measure(:startup_ms, context.startup_ms)
  end

  defp begin_input(state, turn) do
    observer = self()
    started = now()
    attribution = Attribution.begin_input(state.attribution, turn, started)

    {:ok, _} =
      Task.Supervisor.start_child(state.tasks, fn -> Room.feed(state.context, turn, observer) end)

    %{state | input_started: started, turn: turn, attribution: attribution}
  end

  defp until(state, phase) do
    loop(%{state | deadline: min(state.deadline, now() + 15_000)}, phase)
  end

  defp loop(state, phase) do
    if now() > state.deadline,
      do:
        raise(
          "call deadline in #{phase}: #{inspect(Map.take(state, [:completed, :interruptions, :input_frames, :input_rejections, :caller_transcripts, :agent_transcripts, :turn]))}"
        )

    state =
      receive do
        {:input_result, result, elapsed} ->
          state
          |> measure(:input_acceptance_ms, elapsed)
          |> Map.update!(:input_frames, &(&1 + 1))
          |> Map.update!(:input_rejections, &(&1 + if(result == :ok, do: 0, else: 1)))

        {:call_load, {:first_audio, turn, at}} ->
          observe(state, :sink, turn, at, :first_audio_ms)

        {:input_finished, turn} ->
          %{
            state
            | input_finished: turn,
              attribution: Attribution.finish_input(state.attribution, turn)
          }

        {:call_load, {:playback_ack, turn, at}} ->
          measure(
            state,
            :playback_ack_ms,
            Attribution.elapsed(state.attribution, :sink, turn, at)
          )

        {:vxpipe_event, %ParticipantTurnStarted{} = event} ->
          validate_event!(state.context, event, :caller)
          observe(state, :caller, event.correlation_id, now(), :speech_onset_ms)

        {:vxpipe_event, %AgentSpeechStarted{} = event} ->
          validate_event!(state.context, event, :agent)
          observe(state, :public, event.correlation_id, now(), :agent_speech_onset_ms)

        {:vxpipe_event, %ParticipantTranscription{final: true, text: "HI"}} ->
          Map.update!(state, :caller_transcripts, &(&1 + 1))

        {:vxpipe_event, %TextOutput{text: "RECEIVED HI"}} ->
          Map.update!(state, :agent_transcripts, &(&1 + 1))

        {:vxpipe_event, %AgentTurnInterrupted{} = event} ->
          validate_event!(state.context, event, :agent)

          if state.barge_at == nil or
               Attribution.input(state.attribution, :public, event.correlation_id) != 2,
             do: raise("unexpected interruption")

          state
          |> measure(:interruption_ms, now() - state.barge_at)
          |> Map.update!(:interruptions, &(&1 + 1))

        {:vxpipe_event, %AgentTurnCompleted{} = event} ->
          validate_event!(state.context, event, :agent)

          state
          |> measure(
            :turn_completion_ms,
            Attribution.elapsed(state.attribution, :public, event.correlation_id, now())
          )
          |> Map.update!(:completed, &(&1 + 1))

        {:vxpipe_event, %AgentTurnFailed{}} ->
          raise "public agent turn failed"

        _other ->
          state
      after
        20 -> state
      end

    state =
      if phase == :barge and state.turn == 2 and Attribution.ready?(state.attribution) do
        next = begin_input(state, 3)
        %{next | barge_at: next.input_started}
      else
        state
      end

    {mailbox, memory} = sample(state.context)

    if mailbox > 2_000 or memory > 128_000_000 or :erlang.memory(:total) > 1_000_000_000,
      do: raise("load resource bound")

    state = %{
      state
      | mailbox_peak: max(mailbox, state.mailbox_peak),
        memory_peak: max(memory, state.memory_peak)
    }

    done =
      case phase do
        :ordinary -> state.completed >= 1
        :barge -> state.completed >= 2 and state.interruptions == 1
        :survive -> state.completed >= 3
      end

    settled =
      length(state.samples.playback_ack_ms) >= state.completed and
        state.agent_transcripts >= state.completed and state.input_finished == state.turn and
        Attribution.ready?(state.attribution)

    if done and settled, do: %{state | deadline: now() + 90_000}, else: loop(state, phase)
  end

  defp observe(state, kind, id, at, metric) do
    {attribution, elapsed} = Attribution.observe(state.attribution, kind, id, at)
    measure(%{state | attribution: attribution}, metric, elapsed)
  end

  defp validate_event!(context, event, role) do
    participant =
      if role == :caller, do: context.plan.entry_caller, else: context.plan.entry_receiver

    expected = Map.fetch!(context.plan.participants, participant).participant_id

    if event.tenant_id != context.command.tenant_id or event.room_id != context.command.room_id or
         event.incarnation_id != context.command.incarnation_id or
         event.connection_id != context.command.connection_id or event.participant_id != expected,
       do: raise(ArgumentError, "uncorrelated public event identity")
  end

  defp input_drops(%{mode: :llm_tts} = context, state) do
    case IngressObserver.stats(context.ingress_observer, context.attachment.media_ingress) do
      nil ->
        %{rejected: state.input_rejections, ingress_dropped: nil, delivered: nil}

      stats ->
        %{
          rejected: state.input_rejections,
          ingress_dropped: stats.dropped,
          delivered: stats.delivered
        }
    end
  end

  defp input_drops(context, state) do
    case CallEngine.speech_to_speech_input_configuration(context.attachment) do
      {:ok, %{ingress: ingress}} ->
        %{
          rejected: state.input_rejections,
          ingress_dropped: STSIngress.stats(ingress).dropped,
          delivered: nil
        }

      _ ->
        %{rejected: state.input_rejections, ingress_dropped: nil, delivered: nil}
    end
  end

  defp sample(context) do
    Enum.reduce(
      [self(), context.sink, context.connection | Room.members(context.root)],
      {0, 0},
      fn pid, {q, memory} ->
        case Process.info(pid, [:message_queue_len, :memory]) do
          nil ->
            {q, memory}

          info ->
            {q + Keyword.fetch!(info, :message_queue_len), memory + Keyword.fetch!(info, :memory)}
        end
      end
    )
  end

  defp measure(state, name, value), do: update_in(state.samples[name], &[value | &1])

  defp barrier(kind, count),
    do:
      Enum.map(1..count, fn _ ->
        receive do
          {^kind, pid} -> pid
          {:call_failed, message} -> raise message
        after
          90_000 -> raise "#{kind} barrier timeout"
        end
      end)

  defp summarize(mode, calls, results, duration) do
    good = Enum.filter(results, &(&1.errors == []))

    %{
      mode: mode,
      schedulers: System.schedulers_online(),
      otp: System.otp_release(),
      elixir: System.version(),
      ready_calls: calls,
      duration_ms: duration,
      completed_turns: Enum.sum(Enum.map(good, & &1.completed)),
      interruptions: Enum.sum(Enum.map(good, & &1.interruptions)),
      surviving_calls: Enum.count(good, & &1.survived),
      cleaned_calls: Enum.count(good, & &1.cleaned),
      errors: Enum.flat_map(results, & &1.errors),
      calls: Enum.map(results, &Map.delete(&1, :samples)),
      milliseconds:
        Map.new(@measurements, fn name ->
          {name, Metrics.percentiles(Enum.flat_map(good, &Map.fetch!(&1.samples, name)))}
        end)
    }
  end

  defp now, do: System.monotonic_time(:microsecond) / 1_000
end
