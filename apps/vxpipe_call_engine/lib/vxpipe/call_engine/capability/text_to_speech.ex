defmodule Vxpipe.CallEngine.Capability.TextToSpeech do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Capability.TextToSpeech.{Output, Usage}
  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.Readiness.{Resource, Watch}
  alias Vxpipe.CallEngine.Speech.{Audio, Event, Session}
  alias Vxpipe.CallEngine.Telemetry
  alias Vxpipe.CallEngine.TextToSpeechRequest

  @call_timeout 5_000
  @maximum_text_bytes 65_536

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, Keyword.take(options, [:name]))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :participant_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness(capability) do
    GenServer.call(capability, :readiness, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec synthesize(pid(), TextToSpeechRequest.t()) ::
          :ok | {:error, :invalid_request | :queue_full | :unavailable}
  def synthesize(capability, %TextToSpeechRequest{} = request) do
    GenServer.call(capability, {:synthesize, request}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec interrupt(pid()) ::
          {:ok, [{TextToSpeechRequest.t(), non_neg_integer()}]} | {:error, :unavailable}
  def interrupt(capability) when is_pid(capability) do
    GenServer.call(capability, :interrupt, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    {provider, provider_options} = Keyword.fetch!(options, :provider)
    scope = Keyword.fetch!(options, :speech_scope)

    session_options = [
      owner: self(),
      consumer: self(),
      provider: provider,
      options: provider_options,
      private: Keyword.get(options, :provider_private, []),
      usage: true
    ]

    case Session.start(scope, session_options) do
      {:ok, session, :starting} ->
        {:ok,
         %{
           cancellation: nil,
           current: nil,
           descriptor: nil,
           maximum_requests: Keyword.get(options, :maximum_requests, 4),
           output: Keyword.fetch!(options, :output),
           owner: owner,
           pending: :queue.new(),
           provider: provider,
           readiness_resource: readiness_resource(options),
           readiness_status: :preparing,
           session: session,
           usage_context: Keyword.get(options, :usage)
         }}

      {:error, _reason} ->
        Telemetry.provider_failure(:tts, provider, :provider_failed)
        {:stop, :provider_start_failed}
    end
  end

  @impl true
  def handle_call(:readiness, _from, state),
    do: {:reply, {:ok, state.readiness_resource, state.readiness_status}, state}

  def handle_call({:synthesize, request}, _from, state) do
    cond do
      not valid_request?(request) ->
        {:reply, {:error, :invalid_request}, state}

      state.current == nil ->
        case start_request(request, state) do
          {:ok, state} ->
            {:reply, :ok, state}

          {:error, reason, state} ->
            stop_unavailable(reason, {:error, :unavailable}, state)
        end

      :queue.len(state.pending) >= state.maximum_requests ->
        {:reply, {:error, :queue_full}, state}

      true ->
        {:reply, :ok, %{state | pending: :queue.in(request, state.pending)}}
    end
  end

  def handle_call(:interrupt, _from, %{current: nil} = state) do
    interrupted = Enum.map(:queue.to_list(state.pending), &{&1, 0})
    {:reply, {:ok, interrupted}, %{state | pending: :queue.new()}}
  end

  def handle_call(:interrupt, _from, %{cancellation: cancellation} = state)
      when not is_nil(cancellation) do
    interrupted = Enum.map(:queue.to_list(state.pending), &{&1, 0})
    {:reply, {:ok, interrupted}, %{state | pending: :queue.new()}}
  end

  def handle_call(:interrupt, from, state) do
    current = state.current
    pending = Enum.map(:queue.to_list(state.pending), &{&1, 0})

    with {:ok, ticket} <- Session.fence_output(state.session, current.handle),
         {:ok, played_ms, state} <- interrupt_output(current, state),
         {:ok, request_id} <- Session.request_cancel(state.session, ticket, played_ms) do
      cancellation = %{
        accepted?: false,
        discarded?: false,
        from: from,
        interrupted: [{current.request, played_ms} | pending],
        played_ms: played_ms,
        request_id: request_id,
        terminal?: current.phase in [:finishing, :draining],
        ticket: ticket
      }

      {:noreply,
       %{
         state
         | cancellation: cancellation,
           current: %{current | phase: :cancelling},
           pending: :queue.new()
       }}
    else
      {:error, :audio_output_failed, state} ->
        stop_unavailable(:audio_output_failed, {:error, :unavailable}, state)

      _failure ->
        stop_unavailable(:provider_failed, {:error, :unavailable}, state)
    end
  end

  @impl true
  def handle_info({:vxpipe_speech, %Event{kind: :ready, session: session} = event}, state)
      when session == state.session do
    with :ok <- Session.ack(session, event),
         {:ok, descriptor} <- Session.describe(session) do
      # Startup readiness collectors re-probe on this instead of waiting for a poll.
      Watch.changed()
      {:noreply, %{state | descriptor: descriptor, readiness_status: :ready}}
    else
      _failure -> stop_unavailable(:provider_failed, state)
    end
  end

  def handle_info({:vxpipe_speech, %Event{session: session} = event}, state)
      when session == state.session do
    handle_event(event, state)
  end

  def handle_info({:vxpipe_speech_audio, %Audio{session: session} = audio}, state)
      when session == state.session do
    handle_audio(audio, state)
  end

  def handle_info({:vxpipe_speech_closed, session, _reason}, %{session: session} = state),
    do: stop_unavailable(:provider_failed, state)

  def handle_info(
        {:vxpipe_tts_output, output, reference, {:push, audio, result}},
        %{output: output, current: %{handle: %{ref: reference}} = current} = state
      ) do
    cond do
      result == :ok and current.phase != :cancelling ->
        case Session.ack_audio(state.session, audio) do
          :ok -> {:noreply, state}
          {:error, _reason} -> stop_unavailable(:audio_output_failed, state)
        end

      result in [:ok, {:error, :interrupted}, {:error, :stale_output_generation}] and
          current.phase == :cancelling ->
        {:noreply, state}

      result == {:error, :stale_output_generation} and current.request.purpose == :agent_turn ->
        discard_obsolete_output(state)

      true ->
        stop_unavailable(:audio_output_failed, state)
    end
  end

  def handle_info(
        {:vxpipe_tts_output, output, reference, {:finish, result}},
        %{
          output: output,
          current: %{handle: %{ref: reference}, phase: :cancelling}
        } = state
      )
      when result in [:ok, {:error, :interrupted}],
      do: {:noreply, state}

  def handle_info(
        {:vxpipe_tts_output, output, reference, {:finish, :ok}},
        %{output: output, current: %{handle: %{ref: reference}} = current} = state
      ) do
    current = %{current | phase: :draining}
    state = %{state | current: current}

    case Map.get(current, :playback_completed_ms) do
      nil -> {:noreply, state}
      total_ms -> complete_playback(total_ms, state)
    end
  end

  def handle_info(
        {:vxpipe_tts_output, output, reference, {:finish, _error}},
        %{output: output, current: %{handle: %{ref: reference}}} = state
      ),
      do: stop_unavailable(:audio_output_failed, state)

  def handle_info(
        {:vxpipe_audio_playback, sink, turn, :started},
        %{current: %{phase: phase, request: request}} = state
      )
      when sink == request.output_sink and turn == request.correlation_id and
             phase != :cancelling do
    send(state.owner, {:vxpipe_tts_playback, self(), request, :started})
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_audio_playback, sink, turn, {:progress, played_ms, total_ms} = progress},
        %{current: %{phase: phase, request: request} = current} = state
      )
      when sink == request.output_sink and turn == request.correlation_id and
             is_integer(played_ms) and played_ms > 0 and is_integer(total_ms) and
             total_ms > played_ms and phase != :cancelling do
    send(state.owner, {:vxpipe_tts_playback, self(), request, progress})
    {:noreply, %{state | current: Map.put(current, :played_ms, played_ms)}}
  end

  def handle_info(
        {:vxpipe_audio_playback, sink, turn, {:completed, total_ms}},
        %{current: %{phase: :draining, request: request}} = state
      )
      when sink == request.output_sink and turn == request.correlation_id and
             is_integer(total_ms) and total_ms >= 0,
      do: complete_playback(total_ms, state)

  def handle_info(
        {:vxpipe_audio_playback, sink, turn, {:completed, total_ms}},
        %{current: %{phase: :finishing, request: request} = current} = state
      )
      when sink == request.output_sink and turn == request.correlation_id and
             is_integer(total_ms) and total_ms >= 0 do
    {:noreply, %{state | current: Map.put(current, :playback_completed_ms, total_ms)}}
  end

  def handle_info(
        message,
        %{cancellation: %{accepted?: false, request_id: request_id} = cancellation} = state
      ) do
    case Session.cancellation_response(message, request_id) do
      {:reply, {:ok, _playback}} ->
        if cancellation.from != nil do
          GenServer.reply(cancellation.from, {:ok, cancellation.interrupted})
        end

        maybe_finish_cancellation(%{
          state
          | cancellation: %{cancellation | accepted?: true, from: nil}
        })

      {:reply, {:error, _reason}} ->
        stop_unavailable(:provider_failed, state)

      {:error, _reason} ->
        stop_unavailable(:provider_failed, state)

      :no_reply ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = Session.close(state.session)
    :ok
  end

  defp handle_event(%Event{kind: :input_submitted} = event, state) do
    case state.current do
      %{handle: %{ref: reference}} = current when reference == event.request_ref ->
        current =
          Usage.observe_event(current, event, state.usage_context, state.descriptor.format)

        state = %{state | current: current}

        case Session.ack(state.session, event) do
          :ok ->
            {:noreply, state}

          {:error, _reason} ->
            stop_unavailable(:provider_failed, state)
        end

      _other ->
        stop_unavailable(:invalid_provider_message, state)
    end
  end

  defp handle_event(%Event{kind: :completed} = event, state) do
    case state.current do
      %{handle: %{ref: reference}, request: request} = current
      when reference == event.request_ref ->
        current =
          Usage.observe_event(current, event, state.usage_context, state.descriptor.format)

        state = %{state | current: current}

        with :ok <- Session.ack(state.session, event),
             :ok <- Output.finish(state.output, self(), reference, request) do
          {:noreply, %{state | current: %{current | phase: :finishing}}}
        else
          _failure -> stop_unavailable(:audio_output_failed, state)
        end

      _other ->
        stop_unavailable(:invalid_provider_message, state)
    end
  end

  defp handle_event(%Event{kind: :cancelled} = event, state) do
    case state.current do
      %{handle: %{ref: reference}} = current
      when reference == event.request_ref and current.phase == :cancelling ->
        current =
          Usage.observe_event(current, event, state.usage_context, state.descriptor.format)

        state = %{state | current: current}

        case Session.ack(state.session, event) do
          :ok ->
            cancellation = %{state.cancellation | terminal?: true}
            maybe_finish_cancellation(%{state | cancellation: cancellation})

          {:error, _reason} ->
            stop_unavailable(:provider_failed, state)
        end

      _other ->
        stop_unavailable(:invalid_provider_message, state)
    end
  end

  defp handle_event(%Event{kind: :failed, request_ref: reference} = event, state) do
    case state.current do
      %{handle: %{ref: ^reference}} ->
        case Session.ack(state.session, event) do
          :ok -> stop_unavailable(:provider_failed, state)
          {:error, _reason} -> stop_unavailable(:invalid_provider_message, state)
        end

      _other ->
        stop_unavailable(:invalid_provider_message, state)
    end
  end

  defp handle_event(_event, state), do: stop_unavailable(:invalid_provider_message, state)

  defp handle_audio(
         %Audio{request_ref: reference} = audio,
         %{current: %{handle: %{ref: reference}, phase: :cancelling} = current} = state
       ) do
    {:noreply, %{state | current: Usage.observe_audio(current, audio)}}
  end

  defp handle_audio(%Audio{request_ref: reference} = audio, state) do
    case state.current do
      %{handle: %{ref: ^reference}, phase: phase, request: request} = current
      when phase not in [:cancelling, :finishing, :draining] ->
        current = Usage.observe_audio(current, audio)
        state = %{state | current: current}

        with :ok <- Session.validate_audio(state.session, audio),
             :ok <-
               Output.push(
                 state.output,
                 self(),
                 audio,
                 request.output_sink,
                 output_frame(request, audio, state)
               ) do
          current = observe_first_audio(current, state.provider)
          {:noreply, %{state | current: current}}
        else
          _failure -> stop_unavailable(:audio_output_failed, state)
        end

      _other ->
        stop_unavailable(:invalid_provider_message, state)
    end
  end

  defp start_request(request, state) do
    case Session.speak(state.session, request.text) do
      {:ok, handle} ->
        current = %{
          first_audio_observed?: false,
          handle: handle,
          phase: :submitted,
          played_ms: 0,
          request: request,
          started_at: Telemetry.started_at(),
          usage: nil
        }

        {:ok, %{state | current: current}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp start_next(state) do
    case :queue.out(state.pending) do
      {{:value, request}, pending} -> start_request(request, %{state | pending: pending})
      {:empty, _pending} -> {:ok, state}
    end
  end

  defp interrupt_output(current, state) do
    case Output.interrupt(state.output, current.handle.ref, current.request, self()) do
      {:ok, played_ms} -> {:ok, played_ms, state}
      {:error, :wrong_turn} -> {:ok, 0, state}
      {:error, _reason} -> {:error, :audio_output_failed, state}
    end
  end

  defp discard_obsolete_output(state) do
    current = state.current

    with {:ok, ticket} <- Session.fence_output(state.session, current.handle),
         {:ok, played_ms, state} <- interrupt_output(current, state),
         {:ok, request_id} <- Session.request_cancel(state.session, ticket, played_ms) do
      cancellation = %{
        accepted?: false,
        discarded?: true,
        from: nil,
        interrupted: [],
        played_ms: played_ms,
        request_id: request_id,
        terminal?: current.phase in [:finishing, :draining],
        ticket: ticket
      }

      {:noreply, %{state | cancellation: cancellation, current: %{current | phase: :cancelling}}}
    else
      {:error, :audio_output_failed, state} -> stop_unavailable(:audio_output_failed, state)
      _failure -> stop_unavailable(:provider_failed, state)
    end
  end

  defp finish_cancellation(state) do
    _current = Usage.finish(state.current, :cancelled, state.owner)

    if state.cancellation.discarded? do
      send(state.owner, {:vxpipe_tts_playback, self(), state.current.request, :discarded})
    end

    state = %{state | cancellation: nil, current: nil}

    case start_next(state) do
      {:ok, state} -> {:noreply, state}
      {:error, reason, state} -> stop_unavailable(reason, state)
    end
  end

  defp maybe_finish_cancellation(%{cancellation: %{accepted?: true, terminal?: true}} = state),
    do: finish_cancellation(state)

  defp maybe_finish_cancellation(state), do: {:noreply, state}

  defp complete_playback(total_ms, state) do
    request = state.current.request
    handle = state.current.handle

    case Session.settle_output(state.session, handle, total_ms) do
      :ok ->
        _current = Usage.finish(state.current, :succeeded, state.owner)
        send(state.owner, {:vxpipe_tts_playback, self(), request, :completed})
        state = %{state | current: nil}

        case start_next(state) do
          {:ok, state} -> {:noreply, state}
          {:error, reason, state} -> stop_unavailable(reason, state)
        end

      {:error, _reason} ->
        stop_unavailable(:provider_failed, state)
    end
  end

  defp output_frame(request, %Audio{payload: payload}, state) do
    format = state.descriptor.format

    struct!(AudioOutputFrame, %{
      tenant_id: request.tenant_id,
      room_id: request.room_id,
      incarnation_id: request.incarnation_id,
      participant_id: request.participant_id,
      connection_id: request.connection_id,
      command_id: request.command_id,
      correlation_id: request.correlation_id,
      codec: format.encoding,
      sample_rate: format.sample_rate,
      channels: format.channels,
      byte_order: format.byte_order,
      payload: payload,
      audio_scope: audio_scope(request.purpose),
      output_generation: request.output_generation,
      reply_to: self()
    })
  end

  defp readiness_resource(options) do
    %Resource{
      kind: :text_to_speech,
      scope: {:participant, Keyword.fetch!(options, :participant_id)},
      binding: Keyword.get(options, :readiness_binding),
      instance: self(),
      generation: make_ref(),
      configuration: Resource.signature(Keyword.fetch!(options, :provider)),
      policy_interval: nil,
      adapter: __MODULE__
    }
  end

  defp valid_request?(request) do
    Enum.all?(
      [
        request.tenant_id,
        request.room_id,
        request.incarnation_id,
        request.participant_id,
        request.source_participant_id,
        request.connection_id,
        request.command_id,
        request.correlation_id
      ],
      &(is_binary(&1) and byte_size(&1) > 0)
    ) and is_binary(request.text) and byte_size(request.text) > 0 and
      byte_size(request.text) <= @maximum_text_bytes and is_pid(request.output_sink)
  end

  defp observe_first_audio(%{first_audio_observed?: false} = current, provider) do
    Telemetry.tts_first_audio(current.started_at, provider)
    %{current | first_audio_observed?: true}
  end

  defp observe_first_audio(current, _provider), do: current

  defp audio_scope(:transfer_briefing), do: :private
  defp audio_scope(_purpose), do: :conversation

  defp stop_unavailable(reason, state) do
    _current = Usage.finish(state.current, :failed, state.owner)
    Telemetry.provider_failure(:tts, state.provider, reason)
    send(state.owner, {:vxpipe_tts_unavailable, self(), reason})
    {:stop, reason, state}
  end

  defp stop_unavailable(reason, reply, state) do
    _current = Usage.finish(state.current, :failed, state.owner)
    Telemetry.provider_failure(:tts, state.provider, reason)
    send(state.owner, {:vxpipe_tts_unavailable, self(), reason})
    {:stop, reason, reply, state}
  end
end
