defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.Output do
  @moduledoc """
  Output admission, playback settlement and agent-output recognition for STS.

  Runs within the capability process; it introduces no process or mailbox.
  Pending turns, sink credit and the optional recognizer share the output
  lifecycle, independently of caller input and tool-event handling.
  """

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Usage
  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, OutputSink}
  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.Speech.{Audio, Event, OutputTurn, Session}
  alias Vxpipe.CallEngine.Telemetry

  @max_pending_turns 16
  @max_output_stt_buffer 16
  @max_output_stt_restart_attempts 10
  @output_stt_retry_ms 200

  def admit_reply(turn_ref, state) do
    cond do
      not is_nil(state.active_output) ->
        queue_turn(state, turn_ref)

      output_stt_waiting?(state) ->
        queue_turn(state, turn_ref)

      true ->
        case Session.admit_output(state.session, turn_ref) do
          {:ok, handle} ->
            sink_turn = inspect(handle.ref)

            output = %{
              output: handle,
              provider_turn: turn_ref,
              transcript_interval:
                Vxpipe.CallEngine.Capability.SpeechToSpeech.Input.transcript_interval(
                  state,
                  state.agent_id
                ),
              sink_turn: sink_turn,
              pending_text: nil,
              stt_text: nil,
              stt_bytes: 0,
              text_deadline: nil,
              generation_done?: false,
              playback_done?: false,
              played_ms: 0
            }

            send(state.owner, {:vxpipe_sts_turn_started, self(), state.agent_id, turn_ref})
            {:noreply, %{state | active_output: output}}

          {:error, :busy} ->
            queue_turn(state, turn_ref)

          {:error, _reason} ->
            {:noreply, state}
        end
    end
  end

  defp queue_turn(state, turn_ref) do
    cond do
      turn_ref in state.pending_turns ->
        {:noreply, state}

      length(state.pending_turns) >= @max_pending_turns ->
        stop_unavailable(:pending_turn_overflow, state)

      true ->
        {:noreply, %{state | pending_turns: state.pending_turns ++ [turn_ref]}}
    end
  end

  def handle_audio(%Audio{} = audio, state) do
    case state.active_output do
      %{output: %{ref: ref}} = output when ref == audio.request_ref ->
        with :ok <- Session.validate_audio(state.session, audio),
             true <- audio_route_permitted?(state, state.agent_id, state.human_id),
             frame = output_frame(output, audio, state),
             :ok <- OutputSink.push(state.sink, frame),
             :ok <- Session.ack_audio(state.session, audio) do
          {:noreply, feed_output_stt(audio, state)}
        else
          false -> {:noreply, %{state | active_output: nil}}
          _failure -> stop_unavailable(:audio_output_failed, state)
        end

      _other ->
        _ = Session.ack_audio(state.session, audio)
        {:noreply, state}
    end
  end

  def complete_playback(turn, played_ms, state) do
    case state.active_output do
      %{sink_turn: ^turn} = output ->
        state = %{state | active_output: %{output | playback_done?: true, played_ms: played_ms}}
        maybe_finish_turn(state)

      _other ->
        {:noreply, state}
    end
  end

  def maybe_finish_turn(%{active_output: nil} = state), do: {:noreply, state}

  def maybe_finish_turn(%{active_output: output} = state) do
    if output.generation_done? and output.playback_done? and output_text_ready?(output, state) do
      played_ms = output.played_ms

      case Session.settle_output(state.session, output.output, played_ms) do
        :ok ->
          state = cancel_text_deadline(state)
          state = publish_agent_transcript(output, played_ms, state)

          _ =
            emit_turn_usage(
              state,
              output.provider_turn,
              :succeeded,
              played_ms,
              output.stt_bytes || 0
            )

          state = drop_stt_buffer(%{state | active_output: nil, egress_ms: played_ms})

          send(
            state.owner,
            {:vxpipe_sts_turn_completed, self(), state.agent_id, output.provider_turn}
          )

          admit_next_pending(state)

        {:error, _reason} ->
          stop_unavailable(:provider_failed, state)
      end
    else
      {:noreply, arm_text_deadline(state)}
    end
  end

  defp arm_text_deadline(%{active_output: nil} = state), do: state
  defp arm_text_deadline(%{output_stt: nil} = state), do: state

  defp arm_text_deadline(%{active_output: output} = state) do
    cond do
      not output.generation_done? or not output.playback_done? ->
        state

      output.stt_text != nil ->
        state

      output.text_deadline != nil ->
        state

      true ->
        timer =
          Process.send_after(
            self(),
            {:vxpipe_output_stt_timeout, output.provider_turn},
            state.output_stt_timeout_ms
          )

        %{state | active_output: %{output | text_deadline: timer}}
    end
  end

  defp cancel_text_deadline(%{active_output: nil} = state), do: state

  defp cancel_text_deadline(%{active_output: %{text_deadline: nil}} = state), do: state

  defp cancel_text_deadline(%{active_output: %{text_deadline: timer}} = state) do
    _ = Process.cancel_timer(timer)
    %{state | active_output: %{state.active_output | text_deadline: nil}}
  end

  defp drop_stt_buffer(%{output_stt: nil} = state), do: state

  defp drop_stt_buffer(%{output_stt: %{pending_audio: []}} = state), do: state

  defp drop_stt_buffer(%{output_stt: %{pending_audio: pending} = stt} = state) do
    %{
      state
      | output_stt: %{
          stt
          | pending_audio: [],
            dropped_chunks: stt.dropped_chunks + length(pending)
        }
    }
  end

  def notify_output_stt_unavailable(state, reason) do
    send(state.owner, {:vxpipe_sts_output_stt_unavailable, self(), reason})
    :ok
  end

  defp finish_recovered_turn(%{active_output: nil} = state), do: state
  defp finish_recovered_turn(%{output_stt: nil} = state), do: state

  defp finish_recovered_turn(%{active_output: output} = state) do
    if output.generation_done? and output.stt_text == nil do
      case finish_output_stt_input(state) do
        :ok ->
          state

        {:error, reason} ->
          _ = notify_output_stt_unavailable(state, reason)
          state |> fail_output_stt_turn() |> restart_output_stt()
      end
    else
      state
    end
  end

  defp output_text_ready?(_output, %{output_stt: nil}), do: true
  defp output_text_ready?(%{stt_text: :failed}, _state), do: true
  defp output_text_ready?(%{stt_text: text}, _state), do: not is_nil(text)

  defp resolve_agent_text(%{pending_text: text}, %{output_stt: nil}), do: text
  defp resolve_agent_text(%{stt_text: :failed}, _state), do: nil
  defp resolve_agent_text(%{stt_text: text}, _state), do: text

  defp publish_agent_transcript(output, played_ms, state) do
    text = resolve_agent_text(output, state)

    cond do
      is_nil(text) ->
        state

      played_ms <= 0 ->
        send(
          state.owner,
          {:vxpipe_sts_interrupted, self(), state.agent_id, output.provider_turn, 0, :no_prefix}
        )

        state

      transcript_route_permitted?(state, state.agent_id, state.human_id) ->
        send(
          state.owner,
          {:vxpipe_sts_agent_transcript, self(), state.agent_id, text, output.provider_turn,
           played_ms, output.transcript_interval}
        )

        state

      true ->
        state
    end
  end

  def admit_next_pending(%{active_output: nil, pending_turns: [turn | rest]} = state) do
    if output_stt_waiting?(state),
      do: {:noreply, state},
      else: gated_admit(turn, %{state | pending_turns: rest})
  end

  def admit_next_pending(state), do: {:noreply, state}

  defp drain_queue(state) do
    case admit_next_pending(state) do
      {:noreply, state} -> state
    end
  end

  defp gated_admit(turn, state) do
    if audio_route_permitted?(state, state.human_id, state.agent_id) and not state.held? do
      admit_reply(turn, state)
    else
      {:noreply, state}
    end
  end

  def start_output_stt(%{output_stt_options: {nil, _scope, _private}} = state),
    do: {:ok, %{state | output_stt: nil}}

  def start_output_stt(%{output_stt_options: {{module, opts}, scope, private}} = state)
      when not is_nil(scope) do
    session_options = [
      owner: self(),
      consumer: self(),
      provider: module,
      options: opts,
      private: private,
      usage: false
    ]

    case Session.start(scope, session_options) do
      {:ok, session, :starting} ->
        {:ok,
         %{
           state
           | output_stt: %{
               provider: {module, opts},
               session: session,
               ready?: false,
               pending_text: nil,
               pending_audio: [],
               fed_chunks: 0,
               dropped_chunks: 0,
               restarts: 0,
               restart_attempts: 0,
               retry_scheduled?: false,
               recovery_failed?: false
             }
         }}

      {:error, _reason} = error ->
        error
    end
  end

  def start_output_stt(state), do: {:ok, %{state | output_stt: nil}}

  def close_output_stt(%{output_stt: nil}), do: :ok
  def close_output_stt(%{output_stt: %{session: nil}}), do: :ok
  def close_output_stt(%{output_stt: %{session: session}}), do: Session.close(session)

  def restart_output_stt(%{output_stt: nil} = state), do: state

  def restart_output_stt(%{output_stt: %{recovery_failed?: true}} = state), do: state

  # Starts a replacement recognition session, serializing attempts so retired
  # scope entries (which count toward the scope limit until their trees die)
  # can never pile up behind a flood of failing pushes.
  def restart_output_stt(state) do
    previous = state.output_stt
    _ = close_output_stt(state)
    previous = %{previous | session: nil, ready?: false, pending_text: nil}

    if previous.restart_attempts >= @max_output_stt_restart_attempts do
      fail_output_stt_recovery(%{state | output_stt: previous})
    else
      replace_output_stt(state, %{previous | restart_attempts: previous.restart_attempts + 1})
    end
  end

  defp replace_output_stt(state, previous) do
    case start_output_stt(%{state | output_stt: nil}) do
      {:ok, %{output_stt: nil} = state} ->
        %{state | output_stt: previous}

      {:ok, state} ->
        %{state | output_stt: carry_stt_counters(state.output_stt, previous)}

      {:error, _reason} ->
        schedule_output_stt_retry(%{state | output_stt: previous})
    end
  end

  defp carry_stt_counters(fresh, previous) do
    %{
      fresh
      | pending_audio: Map.get(previous, :pending_audio, []),
        fed_chunks: Map.get(previous, :fed_chunks, 0),
        dropped_chunks:
          Map.get(previous, :dropped_chunks, 0) + Map.get(fresh, :dropped_chunks, 0),
        restart_attempts: previous.restart_attempts,
        retry_scheduled?: false
    }
  end

  defp schedule_output_stt_retry(%{output_stt: nil} = state), do: state

  defp schedule_output_stt_retry(%{output_stt: %{recovery_failed?: true}} = state), do: state

  defp schedule_output_stt_retry(state) do
    attempts = Map.get(state.output_stt, :restart_attempts, 0)

    if attempts >= @max_output_stt_restart_attempts do
      fail_output_stt_recovery(state)
    else
      if Map.get(state.output_stt, :retry_scheduled?, false) do
        state
      else
        _ = Process.send_after(self(), :vxpipe_retry_output_stt_start, @output_stt_retry_ms)
        %{state | output_stt: Map.put(state.output_stt, :retry_scheduled?, true)}
      end
    end
  end

  defp fail_output_stt_recovery(state) do
    _ = notify_output_stt_unavailable(state, :restart_failed)
    send(self(), :vxpipe_output_stt_recovery_failed)
    %{state | output_stt: %{state.output_stt | recovery_failed?: true, ready?: false}}
  end

  defp output_stt_waiting?(%{output_stt: nil}), do: false
  defp output_stt_waiting?(%{output_stt: %{ready?: ready?}}), do: not ready?

  defp feed_output_stt(_audio, %{output_stt: nil} = state), do: state
  defp feed_output_stt(_audio, %{active_output: %{stt_text: :failed}} = state), do: state

  defp feed_output_stt(%Audio{payload: payload}, state) do
    state
    |> flush_output_buffer()
    |> buffer_output_audio(payload)
  end

  @doc """
  Routes one STS output PCM payload to the agent-output STT leg.

  Audio arriving before recognition readiness is preserved in a bounded
  buffer instead of being dropped; audio beyond the bound is counted in
  `dropped_chunks`.
  """
  @spec buffer_output_audio(map(), binary()) :: map()
  def buffer_output_audio(%{output_stt: nil} = state, _payload), do: state

  def buffer_output_audio(%{output_stt: %{ready?: false} = stt} = state, payload)
      when is_binary(payload) do
    if length(stt.pending_audio) >= @max_output_stt_buffer do
      %{state | output_stt: %{stt | dropped_chunks: stt.dropped_chunks + 1}}
    else
      %{state | output_stt: %{stt | pending_audio: stt.pending_audio ++ [payload]}}
    end
  end

  def buffer_output_audio(%{output_stt: %{ready?: true}} = state, payload)
      when is_binary(payload) do
    push_stt_payload(state, payload)
  end

  @doc """
  Delivers buffered recognition audio to a ready output-STT session.
  """
  @spec flush_output_buffer(map()) :: map()
  def flush_output_buffer(%{output_stt: %{ready?: true, pending_audio: [_ | _]}} = state) do
    pending = state.output_stt.pending_audio
    state = %{state | output_stt: %{state.output_stt | pending_audio: []}}

    Enum.reduce(pending, state, fn payload, state ->
      push_stt_payload(state, payload)
    end)
  end

  def flush_output_buffer(state), do: state

  defp count_stt_fed(%{active_output: nil} = state, _size) do
    case state.output_stt do
      %{fed_chunks: fed} = stt -> %{state | output_stt: %{stt | fed_chunks: fed + 1}}
      _stt -> state
    end
  end

  defp count_stt_fed(%{active_output: output} = state, size) do
    state = %{state | active_output: %{output | stt_bytes: (output.stt_bytes || 0) + size}}

    case state.output_stt do
      %{fed_chunks: fed} = stt -> %{state | output_stt: %{stt | fed_chunks: fed + 1}}
      _stt -> state
    end
  end

  defp push_stt_payload(%{output_stt: nil} = state, _payload), do: state

  defp push_stt_payload(%{output_stt: %{session: nil}} = state, payload),
    do: state |> buffer_output_audio(payload) |> schedule_output_stt_retry()

  defp push_stt_payload(%{output_stt: %{session: session} = stt} = state, payload) do
    case Session.push_audio(session, payload) do
      :ok ->
        count_stt_fed(state, byte_size(payload))

      {:error, :busy} ->
        %{state | output_stt: %{stt | dropped_chunks: stt.dropped_chunks + 1}}

      {:error, reason} ->
        # Recognition cannot resume halfway through an utterance. Keep the
        # allocation identity until retirement, and reserve the replacement
        # for the next turn rather than feeding it a truncated PCM suffix.
        _ = notify_output_stt_unavailable(state, reason)
        state = fail_output_stt_turn(state)
        restart_output_stt(state)
    end
  end

  def finish_output_stt_input(%{output_stt: nil}), do: :ok
  def finish_output_stt_input(%{active_output: %{stt_text: :failed}}), do: :ok

  def finish_output_stt_input(%{
        output_stt: %{provider: {module, _}, session: session, ready?: true}
      }) do
    if function_exported?(module, :finish_input, 1) do
      case Session.provider(session) do
        provider when is_pid(provider) ->
          try do
            apply(module, :finish_input, [provider])
          catch
            _, _ -> {:error, :unavailable}
          end

        _missing ->
          {:error, :unavailable}
      end
    else
      :ok
    end
  end

  def finish_output_stt_input(_state), do: :ok

  def handle_output_stt_event(%Event{kind: :ready} = event, state) do
    with :ok <- Session.ack(state.output_stt.session, event) do
      state = %{state | output_stt: %{state.output_stt | ready?: true, restart_attempts: 0}}
      state = flush_output_buffer(state)
      state = finish_recovered_turn(state)
      admit_next_pending(state)
    else
      _failure -> handle_output_stt_failure(state)
    end
  end

  def handle_output_stt_event(%Event{kind: :speech_started} = event, state) do
    case Session.ack(state.output_stt.session, event) do
      :ok -> {:noreply, state}
      {:error, _reason} -> handle_output_stt_failure(state)
    end
  end

  def handle_output_stt_event(%Event{kind: :transcript} = event, state) do
    case Session.ack(state.output_stt.session, event) do
      :ok -> {:noreply, %{state | output_stt: %{state.output_stt | pending_text: event.text}}}
      {:error, _reason} -> handle_output_stt_failure(state)
    end
  end

  def handle_output_stt_event(%Event{kind: :turn_ended} = event, state) do
    case Session.ack(state.output_stt.session, event) do
      :ok ->
        state = %{state | output_stt: %{state.output_stt | pending_text: event.text}}

        case state.active_output do
          nil ->
            {:noreply, state}

          output ->
            {:noreply, %{state | active_output: %{output | stt_text: event.text}}}
            |> then(fn {:noreply, state} -> maybe_finish_turn(state) end)
        end

      {:error, _reason} ->
        handle_output_stt_failure(state)
    end
  end

  def handle_output_stt_event(_event, state), do: {:noreply, state}

  def handle_output_stt_failure(state) do
    # Invalidate the old generation before settlement can admit queued work.
    # Its delayed events/close cannot become evidence for the replacement turn.
    state |> fail_output_stt_turn() |> restart_output_stt() |> maybe_finish_turn()
  end

  defp fail_output_stt_turn(state) do
    state = state |> cancel_text_deadline() |> drop_stt_buffer()

    case state.active_output do
      %{} = output ->
        %{state | active_output: %{output | stt_text: :failed}}

      _other ->
        state
    end
  end

  def settle_fenced_output(state, event) do
    handle = %OutputTurn{session: state.session, turn_ref: event.turn_ref, ref: event.request_ref}

    case Session.settle_output(state.session, handle, 0) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp settle_fenced_generation(_state, %{generation_done?: false}, _played_ms), do: :ok

  defp settle_fenced_generation(state, %{output: handle}, played_ms) do
    case Session.settle_output(state.session, handle, played_ms) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  def fence_output(state) do
    case state.active_output do
      nil ->
        {0, state}

      %{sink_turn: turn, provider_turn: provider_turn} = output ->
        played_ms =
          case OutputSink.interrupt(state.sink, turn, self()) do
            {:ok, played} -> played
            {:error, _reason} -> 0
          end

        _ = clear_sink(state)
        _ = interrupt_provider(state, provider_turn)
        _ = settle_fenced_generation(state, output, played_ms)
        _ = emit_turn_usage(state, provider_turn, :cancelled, played_ms, output.stt_bytes || 0)
        state = cancel_text_deadline(state)
        state = drop_stt_buffer(state)
        state = restart_output_stt(state)

        prefix =
          if played_ms > 0 and not is_nil(resolve_agent_text(output, state)),
            do: {:unverified_prefix, resolve_agent_text(output, state)},
            else: :no_prefix

        send(
          state.owner,
          {:vxpipe_sts_interrupted, self(), state.agent_id, provider_turn, played_ms, prefix}
        )

        {played_ms,
         drain_queue(%{
           state
           | active_output: nil,
             fenced_turns: MapSet.put(state.fenced_turns, provider_turn)
         })}
    end
  end

  defp emit_turn_usage(state, provider_turn, outcome, egress_ms, stt_bytes) do
    case state.usage_context do
      nil ->
        :ok

      context ->
        descriptor = state.descriptor || %{}

        observations =
          Usage.turn_observations(
            context,
            descriptor,
            provider_turn,
            outcome,
            egress_ms,
            pcm_bytes_to_ms(stt_bytes),
            state.output_stt != nil
          )

        unless observations == [] do
          send(state.owner, {:vxpipe_usage_observations, self(), observations})
        end

        :ok
    end
  end

  defp pcm_bytes_to_ms(bytes) when is_integer(bytes) and bytes >= 0,
    do: div(bytes * 1_000, 48_000)

  defp pcm_bytes_to_ms(_bytes), do: 0

  defp clear_sink(state) do
    case OutputSink.clear(state.sink) do
      {:ok, _dropped} -> :ok
      {:error, _reason} -> :ok
    end
  end

  def interrupt_provider(state, turn_ref) do
    provider = Session.provider(state.session)

    if is_pid(provider) do
      try do
        apply(state.provider, :interrupt, [provider, turn_ref])
      catch
        _, _ -> :ok
      end
    end

    :ok
  end

  def audio_route_permitted?(%{policy: nil}, _source, _recipient), do: true

  def audio_route_permitted?(%{policy: policy}, source, recipient),
    do: Effective.audio_route_permitted?(policy, source, recipient)

  def transcript_route_permitted?(%{policy: nil}, _source, _recipient), do: true

  def transcript_route_permitted?(%{policy: policy}, source, recipient),
    do: Effective.transcript_route_permitted?(policy, source, recipient)

  defp output_frame(output, %Audio{payload: payload}, state) do
    format = state.descriptor.format
    identity = state.frame_identity

    struct!(AudioOutputFrame, %{
      tenant_id: Map.get(identity, :tenant_id, "tenant"),
      room_id: Map.get(identity, :room_id, "room"),
      incarnation_id: Map.get(identity, :incarnation_id, "incarnation"),
      participant_id: state.agent_id,
      connection_id: Map.get(identity, :connection_id, "connection"),
      command_id: Map.get(identity, :command_id, "command"),
      correlation_id: output.sink_turn,
      codec: format.encoding,
      sample_rate: format.sample_rate,
      channels: format.channels,
      byte_order: format.byte_order,
      payload: payload,
      audio_scope: :conversation,
      output_generation: state.output_generation,
      reply_to: self()
    })
  end

  def stop_unavailable(reason, state) do
    Telemetry.provider_failure(:sts, state.provider, reason)

    case state.active_output do
      %{provider_turn: turn, played_ms: played, stt_bytes: stt_bytes} ->
        _ = emit_turn_usage(state, turn, :failed, played, stt_bytes || 0)

      _no_active ->
        :ok
    end

    send(state.owner, {:vxpipe_sts_unavailable, self(), reason})
    {:stop, reason, state}
  end
end
