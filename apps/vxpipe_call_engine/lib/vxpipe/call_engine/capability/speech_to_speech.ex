defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech do
  @moduledoc """
  Agent-owned speech-to-speech capability.

  Lives under the room incarnation's `RoomCapabilitySupervisor` as part of the
  agent participant's temporary subtree. Owns one STS `Speech` allocation (and,
  when selected, one agent-scoped output-STT allocation fed only by STS output
  audio). The provider never publishes to the room; this capability forwards
  policy-checked evidence to its owner (the room authority), which remains the
  only transcript publisher.
  """

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Media.OutputSink
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.Speech.{Audio, Event, Session}

  import Vxpipe.CallEngine.Capability.SpeechToSpeech.Output,
    only: [
      admit_reply: 3,
      admit_response: 4,
      retire_stale_pending: 1,
      handle_audio: 2,
      complete_playback: 3,
      notify_output_stt_unavailable: 2,
      admit_next_pending: 1,
      start_output_stt: 1,
      close_output_stt: 1,
      restart_output_stt: 1,
      handle_output_stt_event: 2,
      handle_output_stt_failure: 1,
      fence_output: 1,
      fence_output: 2,
      finish_output_stt_input: 1,
      settle_fenced_output: 2,
      interrupt_provider: 2,
      stop_unavailable: 2,
      audio_route_permitted?: 3
    ]

  alias Vxpipe.CallEngine.Telemetry

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.{
    CallerEvents,
    Input,
    OutputTranscript,
    ResponseOrigins,
    ToolEvents
  }

  @call_timeout 5_000
  @default_output_stt_timeout_ms 5_000
  @max_open_input_turns 16

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, Keyword.take(options, [:name]))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :agent_id)},
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

  @spec push_audio(pid(), String.t(), binary()) ::
          :ok | {:error, :source_mismatch | :policy_denied | :held | :not_ready | term()}
  def push_audio(capability, source_id, pcm) when is_pid(capability) do
    GenServer.call(capability, {:push_audio, source_id, pcm}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def input_format(capability), do: GenServer.call(capability, :input_format, @call_timeout)

  def bind_input(capability, ingress),
    do: GenServer.call(capability, {:bind_input, ingress}, @call_timeout)

  @spec push_text(pid(), String.t()) :: :ok | {:error, term()}
  def push_text(capability, text) when is_pid(capability) and is_binary(text) do
    GenServer.call(capability, {:push_text, text}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec input_activity(pid(), :started | :ended) :: :ok | {:error, term()}
  def input_activity(capability, boundary) when is_pid(capability) do
    GenServer.call(capability, {:input_activity, boundary}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec interrupt(pid()) :: {:ok, non_neg_integer()} | {:error, term()}
  def interrupt(capability) when is_pid(capability) do
    GenServer.call(capability, :interrupt, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec hold(pid()) :: :ok | {:error, term()}
  def hold(capability) when is_pid(capability) do
    GenServer.call(capability, :hold, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec apply_policy(pid(), term()) :: :ok | {:error, term()}
  def apply_policy(capability, policy) when is_pid(capability) do
    GenServer.call(capability, {:apply_policy, policy}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec release(pid()) :: :ok | {:error, term()}
  @spec release(pid(), reference()) :: :ok | {:error, term()}
  def release(capability, epoch \\ make_ref()) when is_pid(capability) and is_reference(epoch) do
    GenServer.call(capability, {:release, epoch}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec send_tool_result(pid(), reference(), term()) :: :ok | {:error, term()}
  def send_tool_result(capability, call_ref, result)
      when is_pid(capability) and is_reference(call_ref) do
    GenServer.call(capability, {:send_tool_result, call_ref, result}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    case OutputTranscript.timeout_ms(options) do
      {:ok, timeout} -> init_session(Keyword.put(options, :output_transcript_timeout_ms, timeout))
      {:error, reason} -> {:stop, reason}
    end
  end

  defp init_session(options) do
    owner = Keyword.fetch!(options, :owner)
    {provider, provider_options} = Keyword.fetch!(options, :provider)
    scope = Keyword.fetch!(options, :speech_scope)

    session_options = [
      owner: self(),
      consumer: self(),
      provider: provider,
      options: provider_options,
      private: Keyword.get(options, :provider_private, []),
      usage: false
    ]

    case Session.start(scope, session_options) do
      {:ok, session, :starting} ->
        state = %{
          owner: owner,
          owner_monitor: Process.monitor(owner),
          agent_id: Keyword.fetch!(options, :agent_id),
          human_id: Keyword.fetch!(options, :human_id),
          provider: provider,
          session: session,
          descriptor: nil,
          sink: Keyword.fetch!(options, :sink),
          policy: Keyword.get(options, :policy),
          policy_revision: Keyword.get(options, :policy_revision, 0),
          caller_source: Keyword.get(options, :caller_source, :sts),
          frame_identity: Keyword.get(options, :frame_identity, %{}),
          usage_context:
            normalize_usage_context(
              Keyword.get(options, :usage_context),
              Keyword.get(options, :frame_identity, %{})
            ),
          readiness: :preparing,
          readiness_resource:
            Resource.new(
              :speech_to_speech,
              {:participant, Keyword.fetch!(options, :agent_id)},
              __MODULE__,
              {Keyword.fetch!(options, :provider), Keyword.get(options, :output_stt)}
            ),
          held?: Keyword.get(options, :input_required?, false),
          input_required?: Keyword.get(options, :input_required?, false),
          input: nil,
          input_monitor: nil,
          input_epoch: nil,
          input_policy: nil,
          origin_policy_revision: 0,
          input_contract: nil,
          input_sequence: nil,
          input_turns: MapSet.new(),
          origin_lifecycle_revision: make_ref(),
          response_origins: ResponseOrigins.new(),
          external_activity_origin: nil,
          pending_turns: [],
          tool_turns: MapSet.new(),
          tool_calls: %{},
          fenced_turns: MapSet.new(),
          caller_turns: %{},
          active_output: nil,
          output_generation: Keyword.get(options, :output_generation, 0),
          egress_ms: 0,
          dropped_ingress_chunks: 0,
          output_stt: nil,
          output_stt_options: {
            Keyword.get(options, :output_stt),
            Keyword.get(options, :output_stt_scope),
            Keyword.get(options, :output_stt_private, [])
          },
          output_stt_timeout_ms:
            Keyword.get(options, :output_stt_timeout_ms, @default_output_stt_timeout_ms),
          output_transcript_timeout_ms: Keyword.fetch!(options, :output_transcript_timeout_ms)
        }

        case start_output_stt(state) do
          {:ok, state} -> {:ok, state}
          {:error, _reason} -> {:stop, :provider_start_failed}
        end

      {:error, _reason} ->
        Telemetry.provider_failure(:sts, provider, :provider_failed)
        {:stop, :provider_start_failed}
    end
  end

  @impl true
  def handle_call(:input_format, _from, state), do: {:reply, Input.format(state), state}

  def handle_call({:bind_input, ingress}, {owner, _tag}, state) when is_pid(ingress),
    do: Input.bind(state, ingress, owner)

  def handle_call(:readiness, _from, state) do
    status =
      if state.output_stt != nil and not state.output_stt.ready?,
        do: :preparing,
        else: state.readiness

    resource =
      if state.output_stt do
        %{
          state.readiness_resource
          | configuration:
              Resource.signature(
                {state.readiness_resource.configuration, state.output_stt.session}
              )
        }
      else
        state.readiness_resource
      end

    {:reply, {:ok, resource, status}, state}
  end

  def handle_call({:push_audio, _source, _pcm}, _from, %{held?: true} = state) do
    {:reply, {:error, :held}, state}
  end

  def handle_call({:push_audio, _source, _pcm}, _from, %{input_required?: true} = state),
    do: {:reply, {:error, :framed_input_required}, state}

  def handle_call({:push_audio, source, pcm}, _from, state) do
    cond do
      source != state.human_id ->
        {:reply, {:error, :source_mismatch}, state}

      not audio_route_permitted?(state, state.human_id, state.agent_id) ->
        {:reply, {:error, :policy_denied}, state}

      true ->
        {result, state} = ResponseOrigins.submit(state, {:audio, pcm})
        {:reply, result, state}
    end
  end

  def handle_call({:push_text, _text}, _from, %{held?: true} = state) do
    {:reply, {:error, :held}, state}
  end

  def handle_call({:push_text, text}, _from, state) do
    {result, state} = ResponseOrigins.submit(state, {:text, text})

    case result do
      {:ok, _handle} -> {:reply, :ok, state}
      :ok -> {:reply, :ok, state}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:input_activity, boundary}, _from, state) do
    {result, state} = ResponseOrigins.submit(state, {:activity, boundary})

    case result do
      :ok ->
        state =
          case {state.descriptor.response_start?, boundary} do
            {true, :started} ->
              {:ok, fingerprint} =
                ResponseOrigins.accepted_fingerprint(state, state.response_origins.current)

              %{state | external_activity_origin: fingerprint}

            {true, :ended} ->
              {:ok, fingerprint} =
                ResponseOrigins.accepted_fingerprint(state, state.response_origins.current)

              if fingerprint == state.external_activity_origin,
                do: %{state | external_activity_origin: nil},
                else: state

            _other ->
              state
          end

        {:noreply, state} =
          if boundary == :ended and state.descriptor.response_start?,
            do: admit_next_pending(state),
            else: {:noreply, state}

        {:reply, :ok, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:interrupt, _from, state) do
    {played_ms, state} = fence_output(state)
    state = interrupt_tool_turns(state)
    {:reply, {:ok, played_ms}, state}
  end

  def handle_call(:hold, _from, state) do
    state = Input.hold(state)
    state = %{state | origin_lifecycle_revision: make_ref(), input_turns: MapSet.new()}
    state = state |> interrupt_tool_turns() |> ToolEvents.retire()

    case retire_stale_pending(state) do
      {:ok, state} ->
        {_played, state} = fence_output(state)

        {:noreply, state} =
          if state.descriptor.response_start?,
            do: admit_next_pending(state),
            else: {:noreply, state}

        {:reply, :ok, %{state | external_activity_origin: nil}}

      {:error, _reason} ->
        stop_unavailable(:provider_failed, state)
    end
  end

  def handle_call({:release, epoch}, _from, state) when is_reference(epoch) do
    case Input.release(state, epoch) do
      {:ok, state} ->
        state = %{state | origin_lifecycle_revision: make_ref(), input_turns: MapSet.new()}

        case retire_stale_pending(state) do
          {:ok, state} ->
            {:noreply, state} = admit_next_pending(state)
            {:reply, :ok, state}

          {:error, _reason} ->
            stop_unavailable(:provider_failed, state)
        end

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:apply_policy, policy}, _from, state) do
    state = %{
      state
      | policy: policy,
        policy_revision: state.policy_revision + 1,
        origin_policy_revision: state.origin_policy_revision + 1
    }

    case retire_stale_pending(state) do
      {:ok, state} ->
        if audio_route_permitted?(state, state.human_id, state.agent_id) and
             audio_route_permitted?(state, state.agent_id, state.human_id) do
          {:reply, :ok, state}
        else
          {_played, state} = fence_output(state)
          {:reply, :ok, state}
        end

      {:error, _reason} ->
        stop_unavailable(:provider_failed, state)
    end
  end

  def handle_call({:vxpipe_apply_media_policy, %Snapshot{} = snapshot}, _from, state) do
    case Input.apply_policy(state, snapshot) do
      {:ok, state} ->
        case retire_stale_pending(state) do
          {:ok, state} ->
            {_played, state} =
              if audio_route_permitted?(state, state.human_id, state.agent_id) and
                   audio_route_permitted?(state, state.agent_id, state.human_id),
                 do: {0, state},
                 else: fence_output(state)

            {:reply, :ok, state}

          {:error, _reason} ->
            stop_unavailable(:provider_failed, state)
        end

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:vxpipe_apply_media_policy, _invalid}, _from, state) do
    {:reply, {:error, :invalid_policy}, state}
  end

  def handle_call({:send_tool_result, call_ref, result}, _from, state) do
    provider = Session.provider(state.session)

    cond do
      not ToolEvents.current?(state, call_ref) ->
        {:reply, {:error, :stale_request}, ToolEvents.drop(state, call_ref)}

      not is_pid(provider) ->
        {:reply, {:error, :unavailable}, state}

      true ->
        case apply(state.provider, :send_tool_result, [provider, call_ref, result]) do
          :ok -> {:reply, :ok, ToolEvents.drop(state, call_ref)}
          {:error, _reason} = error -> {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_info(
        {:vxpipe_speech, %Event{session: session, kind: :ready} = event},
        %{session: session} = state
      ) do
    with :ok <- Session.ack(session, event),
         {:ok, descriptor} <- Session.describe(session) do
      case validate_transcript_mode(descriptor, state) do
        :ok ->
          send(state.owner, {:vxpipe_sts_ready, self()})
          {:noreply, %{state | descriptor: descriptor, readiness: :ready}}

        {:error, reason} ->
          stop_unavailable(reason, state)
      end
    else
      _failure -> stop_unavailable(:provider_failed, state)
    end
  end

  def handle_info({:vxpipe_speech, %Event{session: session} = event}, %{session: session} = state) do
    handle_event(event, state)
  end

  def handle_info(
        {:vxpipe_speech, %Event{session: session} = event},
        %{output_stt: %{session: session}} = state
      ) do
    handle_output_stt_event(event, state)
  end

  def handle_info(
        {:vxpipe_speech_audio, %Audio{session: session} = audio},
        %{session: session} = state
      ) do
    handle_audio(audio, state)
  end

  def handle_info({:vxpipe_speech_audio, %Audio{}}, state) do
    {:noreply, state}
  end

  def handle_info({:vxpipe_sts_input, ingress, reference, frame, revision, epoch}, state),
    do: Input.deliver(state, ingress, reference, frame, revision, epoch)

  def handle_info({:DOWN, monitor, :process, _input, _reason}, %{input_monitor: monitor} = state),
    do: stop_unavailable(:input_unavailable, state)

  def handle_info({:vxpipe_speech_closed, session, _reason}, %{session: session} = state) do
    stop_unavailable(:provider_failed, state)
  end

  def handle_info(
        {:vxpipe_speech_closed, session, _reason},
        %{output_stt: %{session: session}} = state
      ) do
    handle_output_stt_failure(state)
  end

  def handle_info(
        {:vxpipe_audio_playback, sink, turn, {:completed, played_ms}},
        %{sink: sink} = state
      ) do
    complete_playback(turn, played_ms, state)
  end

  def handle_info({:vxpipe_audio_playback, _sink, _turn, _progress}, state) do
    {:noreply, state}
  end

  def handle_info({:vxpipe_output_stt_timeout, turn}, state) do
    case state.active_output do
      %{provider_turn: ^turn, stt_text: nil} = output ->
        _ = notify_output_stt_unavailable(state, :timeout)
        state = %{state | active_output: %{output | stt_text: :failed, text_deadline: nil}}
        handle_output_stt_failure(state)

      _settled_or_answered ->
        {:noreply, state}
    end
  end

  def handle_info({:vxpipe_output_transcript_timeout, output_ref}, state),
    do: OutputTranscript.expire(output_ref, state)

  def handle_info(:vxpipe_retry_output_stt_start, %{output_stt: nil} = state) do
    {:noreply, state}
  end

  def handle_info(
        :vxpipe_output_stt_recovery_failed,
        %{output_stt: %{recovery_failed?: true}} = state
      ) do
    stop_unavailable(:output_stt_restart_failed, state)
  end

  def handle_info(:vxpipe_retry_output_stt_start, state) do
    state = %{state | output_stt: Map.put(state.output_stt, :retry_scheduled?, false)}

    if state.output_stt.ready? do
      {:noreply, state}
    else
      {:noreply, restart_output_stt(state)}
    end
  end

  def handle_info({:DOWN, monitor, :process, _owner, _reason}, %{owner_monitor: monitor} = state) do
    {:stop, :shutdown, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = Session.close(state.session)
    _ = close_output_stt(state)
    :ok
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :speech_to_speech_capability)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp track_input_turn(%{descriptor: %{response_start?: false}} = state, _turn),
    do: {:ok, state}

  defp track_input_turn(state, turn) do
    cond do
      MapSet.member?(state.input_turns, turn) ->
        {:ok, state}

      MapSet.size(state.input_turns) >= @max_open_input_turns ->
        {:error, :pending_caller_overflow}

      true ->
        {:ok, %{state | input_turns: MapSet.put(state.input_turns, turn)}}
    end
  end

  defp handle_event(%Event{kind: :speech_started} = event, state) do
    with :ok <- Session.ack(state.session, event),
         {:ok, state} <- track_input_turn(state, event.turn_ref),
         {:ok, state} <- CallerEvents.forward(state, event) do
      send(
        state.owner,
        {:vxpipe_sts_speech_started, self(), state.agent_id, event.turn_ref}
      )

      case state.active_output do
        nil ->
          {:noreply, state}

        _active ->
          {_played, state} = fence_output(state)
          {:noreply, state}
      end
    else
      {:error, :pending_caller_overflow} -> stop_unavailable(:pending_caller_overflow, state)
      _failure -> stop_unavailable(:provider_failed, state)
    end
  end

  defp handle_event(%Event{kind: :input_transcript} = event, state) do
    with :ok <- Session.ack(state.session, event),
         {:ok, state} <- CallerEvents.forward(state, event) do
      {:noreply, state}
    else
      _failure -> stop_unavailable(:provider_failed, state)
    end
  end

  defp handle_event(%Event{kind: :turn_ended} = event, state) do
    with :ok <- Session.ack(state.session, event),
         {:ok, state} <- CallerEvents.forward(state, event) do
      state = %{state | input_turns: MapSet.delete(state.input_turns, event.turn_ref)}

      cond do
        MapSet.member?(state.tool_turns, event.turn_ref) ->
          {:noreply, state}

        state.descriptor.response_start? ->
          admit_next_pending(state)

        state.held? ->
          {:noreply, state}

        true ->
          admit_reply(event.turn_ref, event.sequence, state)
      end
    else
      _failure -> stop_unavailable(:provider_failed, state)
    end
  end

  defp handle_event(%Event{kind: :response_started} = event, state) do
    case Session.ack(state.session, event) do
      :ok -> admit_response(event.turn_ref, event.response_context, event.sequence, state)
      {:error, _reason} -> stop_unavailable(:provider_failed, state)
    end
  end

  defp handle_event(%Event{kind: :output_transcript} = event, state) do
    with :ok <- Session.ack(state.session, event) do
      OutputTranscript.accept(event, state)
    else
      _failure -> stop_unavailable(:provider_failed, state)
    end
  end

  defp handle_event(%Event{kind: :output_completed} = event, state) do
    with :ok <- Session.ack(state.session, event) do
      case state.active_output do
        %{output: %{ref: ref}} when ref == event.request_ref ->
          state = OutputTranscript.acknowledge_generation(state)
          output = state.active_output

          case finish_output_stt_input(state) do
            :ok ->
              case OutputSink.finish(state.sink, output.sink_turn, self()) do
                :ok ->
                  OutputTranscript.generated(state)

                {:error, _reason} ->
                  stop_unavailable(:audio_output_failed, state)
              end

            {:error, reason} ->
              # A rejected finalization need not terminate its provider. Retire
              # that recognition generation before admitting another reply.
              _ = notify_output_stt_unavailable(state, reason)

              case OutputSink.finish(state.sink, output.sink_turn, self()) do
                :ok ->
                  handle_output_stt_failure(%{
                    state
                    | active_output: %{output | generation_done?: true, stt_text: :failed}
                  })

                {:error, _reason} ->
                  stop_unavailable(:audio_output_failed, state)
              end
          end

        _fenced ->
          # Fence-terminal marker for an already-fenced turn: release the
          # channel slot with zero egress, publish nothing, then admit any
          # queued turn whose policy still allows it.
          _ = settle_fenced_output(state, event)
          admit_next_pending(state)
      end
    else
      _failure -> stop_unavailable(:provider_failed, state)
    end
  end

  defp handle_event(%Event{kind: :interrupted} = event, state) do
    with :ok <- Session.ack(state.session, event) do
      if MapSet.member?(state.fenced_turns, event.turn_ref) do
        {:noreply, %{state | fenced_turns: MapSet.delete(state.fenced_turns, event.turn_ref)}}
      else
        case state.active_output do
          %{provider_turn: turn} when turn == event.turn_ref ->
            {_played, state} = fence_output(state, :provider_reported)
            {:noreply, state}

          _other ->
            send(
              state.owner,
              {:vxpipe_sts_interrupted, self(), state.agent_id, event.turn_ref, 0, :no_prefix,
               event.sequence}
            )

            {:noreply, state}
        end
      end
    else
      _failure -> stop_unavailable(:provider_failed, state)
    end
  end

  defp handle_event(%Event{kind: :input_submitted} = event, state) do
    case Session.ack(state.session, event) do
      :ok -> {:noreply, state}
      {:error, _reason} -> stop_unavailable(:provider_failed, state)
    end
  end

  defp handle_event(%Event{kind: kind} = event, state)
       when kind in [:tool_call, :tool_cancelled] do
    with :ok <- Session.ack(state.session, event),
         {:ok, state} <- ToolEvents.forward(state, event) do
      {:noreply, state}
    else
      {:error, :pending_tool_overflow} -> stop_unavailable(:pending_tool_overflow, state)
      {:error, :stale_tool_origin} -> stop_unavailable(:stale_tool_origin, state)
      _failure -> stop_unavailable(:provider_failed, state)
    end
  end

  defp handle_event(_event, state), do: stop_unavailable(:invalid_provider_message, state)

  defp validate_transcript_mode(descriptor, state) do
    {output_stt, _scope, _private} = state.output_stt_options

    cond do
      descriptor.output_transcript? and not is_nil(output_stt) ->
        {:error, :duplicate_transcript_source}

      not descriptor.output_transcript? and is_nil(output_stt) ->
        {:error, :missing_output_transcript}

      true ->
        :ok
    end
  end

  defp interrupt_tool_turns(state) do
    Enum.each(state.tool_turns, &interrupt_provider(state, &1))
    state
  end

  defp normalize_usage_context(nil, _identity), do: nil

  defp normalize_usage_context(context, identity) when is_list(context) do
    normalize_usage_context(Map.new(context), identity)
  end

  defp normalize_usage_context(context, identity) when is_map(context) do
    context =
      context
      |> Map.put_new(:tenant_id, Map.get(identity, :tenant_id))
      |> Map.put_new(:room_id, Map.get(identity, :room_id))
      |> Map.put_new(:incarnation_id, Map.get(identity, :incarnation_id))

    if is_binary(Map.get(context, :call_id)) and is_binary(Map.get(context, :participant_id)) and
         is_binary(Map.get(context, :tenant_id)) do
      context
    else
      nil
    end
  end

  defp normalize_usage_context(_context, _identity), do: nil
end
