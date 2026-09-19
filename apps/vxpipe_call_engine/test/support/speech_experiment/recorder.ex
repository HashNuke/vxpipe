defmodule Vxpipe.CallEngine.SpeechExperiment.Recorder do
  @moduledoc false
  use GenServer
  alias Vxpipe.CallEngine.Event
  alias Vxpipe.CallEngine.TestAudioOutputSink

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def begin_turn(pid), do: GenServer.call(pid, :begin_turn)
  def tail(pid), do: GenServer.call(pid, :tail)
  def result(pid), do: GenServer.call(pid, {:await, :completed}, 10_000)
  def await(pid, kind), do: GenServer.call(pid, {:await, kind}, 5_000)
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  def init(options), do: {:ok, fresh(Keyword.fetch!(options, :observer))}

  def handle_call({:bind, identity}, _from, state),
    do: {:reply, :ok, %{state | identity: identity}}

  def handle_call(:begin_turn, _from, state),
    do: {:reply, :ok, %{fresh(state.observer) | identity: state.identity}}

  def handle_call(:tail, _from, state), do: {:reply, :ok, %{state | tail: now()}}
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  def handle_call({:await, kind}, from, state) do
    if Map.has_key?(state.times, kind) do
      {:reply, response(kind, state), state}
    else
      {:noreply, %{state | waiters: [{kind, from} | state.waiters]}}
    end
  end

  def handle_info({:test_call_ready, _room} = message, state) do
    send(state.observer, message)
    {:noreply, state}
  end

  def handle_info({:experiment_text_received, timestamp}, state),
    do: {:noreply, %{state | times: Map.put_new(state.times, :text_received, timestamp)}}

  def handle_info({:vxpipe_event, event}, state) do
    kind = event_kind(event)

    state =
      case event do
        %Event.ParticipantTranscription{final: true, text: text} -> %{state | transcript: text}
        _ -> state
      end

    {:noreply, record(state, kind, event)}
  end

  def handle_info({:test_audio_output, _sink, frame}, state) do
    {:noreply, record(%{state | output: [frame | state.output]}, :audio, frame)}
  end

  def handle_info({:test_audio_output_finish, sink, turn}, state) do
    state = record(state, :finish, %{correlation_id: turn})
    :ok = TestAudioOutputSink.playback_completed(sink)
    {:noreply, %{state | playback_ack: now()}}
  end

  def handle_info({:test_audio_output_interrupt, _sink, _turn, _played}, state),
    do: {:noreply, record(state, :sink_interrupt, nil)}

  def handle_info(_message, state), do: {:noreply, state}

  defp fresh(observer) do
    %{
      observer: observer,
      identity: %{},
      correlation: nil,
      identity_errors: [],
      started: now(),
      tail: nil,
      playback_ack: nil,
      times: %{},
      counts: %{},
      events: %{},
      output: [],
      transcript: nil,
      waiters: []
    }
  end

  defp record(state, nil, _event), do: state

  defp record(state, kind, event) do
    state = validate_identity(state, kind, event)

    state = %{
      state
      | times: Map.put_new(state.times, kind, now()),
        counts: Map.update(state.counts, kind, 1, &(&1 + 1)),
        events: Map.put(state.events, kind, event)
    }

    {ready, waiting} = Enum.split_with(state.waiters, fn {key, _} -> key == kind end)
    Enum.each(ready, fn {key, from} -> GenServer.reply(from, response(key, state)) end)
    %{state | waiters: waiting}
  end

  defp response(:completed, state) do
    %{
      counts: Map.take(state.counts, [:started, :final, :ended, :text, :completed]),
      transcript: state.transcript,
      valid_correlations?: state.identity_errors == [],
      output:
        state.output
        |> Enum.reverse()
        |> Enum.filter(&(&1.correlation_id == state.correlation))
        |> Enum.map(& &1.payload)
        |> IO.iodata_to_binary(),
      metrics: %{
        speech_start_us: state.times.started - state.started,
        first_text_us: Map.get(state.times, :partial, state.times.final) - state.started,
        turn_end_us: state.times.ended - state.tail,
        first_audio_us: state.times.audio - state.times.text_received,
        sink_finish_us: state.times.finish - state.times.text_received,
        playback_ack_us: state.times.completed - state.playback_ack,
        total_us: state.times.completed - state.started
      }
    }
  end

  defp response(kind, state), do: {Map.fetch!(state.times, kind), Map.fetch!(state.events, kind)}

  defp validate_identity(state, :sink_interrupt, _event), do: state

  defp validate_identity(state, kind, event) do
    state = if kind == :started, do: %{state | correlation: event.correlation_id}, else: state
    identity_ok? = kind == :finish or Map.take(event, Map.keys(state.identity)) == state.identity
    correlation_ok? = kind == :interrupted or event.correlation_id == state.correlation

    if identity_ok? and correlation_ok?,
      do: state,
      else: %{state | identity_errors: [kind | state.identity_errors]}
  end

  defp event_kind(%Event.ParticipantTurnStarted{}), do: :started
  defp event_kind(%Event.ParticipantTranscription{final: true}), do: :final
  defp event_kind(%Event.ParticipantTranscription{text: text}) when text != "", do: :partial
  defp event_kind(%Event.ParticipantTurnCompleted{}), do: :ended
  defp event_kind(%Event.TextOutput{}), do: :text
  defp event_kind(%Event.AgentTurnCompleted{}), do: :completed
  defp event_kind(%Event.AgentTurnInterrupted{}), do: :interrupted
  defp event_kind(_event), do: nil
  defp now, do: System.monotonic_time(:microsecond)
end
