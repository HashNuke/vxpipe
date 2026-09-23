defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.Output do
  @moduledoc """
  Playback settlement and agent-output recognition for STS.

  Runs within the capability process; it introduces no process or mailbox.
  Sink credit and the optional recognizer share the output lifecycle,
  independently of caller input and tool-event handling.
  """

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.{
    OutputRecognition,
    OutputRecognizer,
    OutputTranscript,
    ResponseQueue,
    Usage
  }

  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, OutputSink}
  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.Speech.{Audio, Event, OutputTurn, Session}
  alias Vxpipe.CallEngine.Telemetry

  @max_output_stt_buffer 16
  @max_output_stt_restart_attempts 10
  @output_stt_retry_ms 200

  defdelegate admit_response(turn_ref, context, sequence, state), to: ResponseQueue
  defdelegate admit_reply(turn_ref, sequence, state), to: ResponseQueue
  defdelegate retire_stale_pending(state), to: ResponseQueue
  defdelegate admit_next_pending(state), to: ResponseQueue

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
          false -> discard_denied_audio(audio, state)
          _failure -> stop_unavailable(:audio_output_failed, state)
        end

      _other ->
        _ = Session.ack_audio(state.session, audio)
        {:noreply, state}
    end
  end

  defp discard_denied_audio(audio, state) do
    case Session.ack_audio(state.session, audio) do
      :ok ->
        {_played, state} = fence_output(state)
        {:noreply, state}

      _failure ->
        stop_unavailable(:audio_output_failed, state)
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
              output
            )

          state = drop_stt_buffer(%{state | active_output: nil, egress_ms: played_ms})

          send(
            state.owner,
            {:vxpipe_sts_turn_completed, self(), state.agent_id, output.provider_turn,
             output.owner_sequence}
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
        expires = System.monotonic_time(:millisecond) + state.output_stt_timeout_ms

        timer =
          Process.send_after(
            self(),
            {:vxpipe_output_stt_timeout, output.provider_turn},
            state.output_stt_timeout_ms
          )

        %{state | active_output: %{output | text_deadline: timer, text_expires_at: expires}}
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

  defp output_text_ready?(output, %{output_stt: nil}), do: OutputTranscript.ready?(output)
  defp output_text_ready?(%{stt_text: :failed}, _state), do: true
  defp output_text_ready?(%{stt_text: text}, _state), do: not is_nil(text)

  defp resolve_agent_text(%{pending_text: text}, %{output_stt: nil}), do: text
  defp resolve_agent_text(%{stt_text: :failed}, _state), do: nil
  defp resolve_agent_text(%{stt_text: ""}, _state), do: nil
  defp resolve_agent_text(%{stt_text: text}, _state), do: text

  defp publish_agent_transcript(output, played_ms, state) do
    text = resolve_agent_text(output, state)

    cond do
      is_nil(text) ->
        state

      played_ms <= 0 ->
        send(
          state.owner,
          {:vxpipe_sts_interrupted, self(), state.agent_id, output.provider_turn, 0, :no_prefix,
           output.owner_sequence}
        )

        state

      transcript_route_permitted?(state, state.agent_id, state.human_id) ->
        send(
          state.owner,
          {:vxpipe_sts_agent_transcript, self(), state.agent_id, text, output.provider_turn,
           played_ms, output.transcript_interval, output.owner_sequence}
        )

        state

      true ->
        state
    end
  end

  defp drain_queue(state) do
    case admit_next_pending(state) do
      {:noreply, state} -> state
    end
  end

  defdelegate start_output_stt(state), to: OutputRecognizer, as: :start

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
      state
      |> Map.put(:output_stt, %{stt | dropped_chunks: stt.dropped_chunks + 1})
      |> fail_recognition_usage()
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
        state
        |> Map.put(:output_stt, %{stt | dropped_chunks: stt.dropped_chunks + 1})
        |> fail_recognition_usage()

      {:error, reason} ->
        # Recognition cannot resume halfway through an utterance. Keep the
        # allocation identity until retirement, and reserve the replacement
        # for the next turn rather than feeding it a truncated PCM suffix.
        _ = notify_output_stt_unavailable(state, reason)
        state = fail_output_stt_turn(state)
        restart_output_stt(state)
    end
  end

  defdelegate finish_output_stt_input(state), to: OutputRecognizer, as: :finish_input

  def handle_output_stt_event(%Event{kind: :ready} = event, state) do
    with :ok <- Session.ack(state.output_stt.session, event),
         {:ok, descriptor} <- Session.describe(state.output_stt.session) do
      state = %{
        state
        | output_stt: %{
            state.output_stt
            | ready?: true,
              descriptor: descriptor,
              restart_attempts: 0
          }
      }

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

          %{stt_text: nil} = output ->
            case OutputRecognition.add(output.stt_segments, event.turn_ref, event.text) do
              {:ok, segments} ->
                {:noreply, %{state | active_output: %{output | stt_segments: segments}}}

              {:error, reason} ->
                _ = notify_output_stt_unavailable(state, reason)
                handle_output_stt_failure(state)
            end

          _settled ->
            {:noreply, state}
        end

      {:error, _reason} ->
        handle_output_stt_failure(state)
    end
  end

  def handle_output_stt_event(%Event{kind: :input_finished} = event, state) do
    with :ok <- Session.ack(state.output_stt.session, event),
         %{generation_done?: true, stt_text: nil} = output <- state.active_output,
         :ok <- recognition_deadline(output) do
      outcome = if output.stt_outcome == :failed, do: :failed, else: :succeeded

      output = %{
        output
        | stt_text: OutputRecognition.text(output.stt_segments),
          stt_segments: OutputRecognition.new(),
          stt_outcome: outcome
      }

      state = %{state | active_output: output}
      state |> restart_output_stt() |> maybe_finish_turn()
    else
      {:error, :timeout} ->
        _ = notify_output_stt_unavailable(state, :timeout)
        handle_output_stt_failure(state)

      _invalid ->
        handle_output_stt_failure(state)
    end
  end

  def handle_output_stt_event(_event, state), do: {:noreply, state}

  defp recognition_deadline(%{text_expires_at: nil}), do: :ok

  defp recognition_deadline(%{text_expires_at: deadline}) do
    if System.monotonic_time(:millisecond) < deadline,
      do: :ok,
      else: {:error, :timeout}
  end

  def handle_output_stt_failure(state) do
    # Invalidate the old generation before settlement can admit queued work.
    # Its delayed events/close cannot become evidence for the replacement turn.
    state |> fail_output_stt_turn() |> restart_output_stt() |> maybe_finish_turn()
  end

  defp fail_output_stt_turn(
         %{
           active_output: %{generation_done?: true, stt_outcome: :succeeded, stt_text: text}
         } = state
       )
       when is_binary(text) do
    # A later idle-session failure does not invalidate the acknowledged final
    # for already completed generation. Its evidence belongs to this reply.
    state |> cancel_text_deadline() |> drop_stt_buffer()
  end

  defp fail_output_stt_turn(state) do
    state = state |> cancel_text_deadline() |> drop_stt_buffer()

    case state.active_output do
      %{} = output ->
        %{state | active_output: %{output | stt_text: :failed, stt_outcome: :failed}}

      _other ->
        state
    end
  end

  defp fail_recognition_usage(%{active_output: nil} = state), do: state

  defp fail_recognition_usage(state),
    do: %{state | active_output: %{state.active_output | stt_outcome: :failed}}

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
        _ = emit_turn_usage(state, provider_turn, :cancelled, played_ms, output)
        state = cancel_text_deadline(state)
        state = drop_stt_buffer(state)
        state = restart_output_stt(state)

        prefix =
          if played_ms > 0 and not is_nil(resolve_agent_text(output, state)),
            do: {:unverified_prefix, resolve_agent_text(output, state)},
            else: :no_prefix

        send(
          state.owner,
          {:vxpipe_sts_interrupted, self(), state.agent_id, provider_turn, played_ms, prefix,
           output.owner_sequence}
        )

        {played_ms,
         drain_queue(%{
           state
           | active_output: nil,
             fenced_turns: MapSet.put(state.fenced_turns, provider_turn)
         })}
    end
  end

  defp emit_turn_usage(state, provider_turn, outcome, egress_ms, output) do
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
            recognition_usage(output, outcome)
          )

        unless observations == [] do
          send(state.owner, {:vxpipe_usage_observations, self(), observations})
        end

        :ok
    end
  end

  defp recognition_usage(%{stt_descriptor: nil}, _outcome), do: nil

  defp recognition_usage(output, outcome) do
    %{
      descriptor: output.stt_descriptor,
      accepted_bytes: output.stt_bytes,
      outcome: if(output.stt_outcome == :in_progress, do: outcome, else: output.stt_outcome)
    }
  end

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
      %{provider_turn: turn, played_ms: played} = output ->
        _ = emit_turn_usage(state, turn, :failed, played, output)

      _no_active ->
        :ok
    end

    send(state.owner, {:vxpipe_sts_unavailable, self(), reason})
    {:stop, reason, state}
  end
end
