defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.Session do
  @moduledoc """
  Credential-free local provider that behaves like GPT-Live.
  It shares the provider-neutral `Speech.Duplex.TurnInference`,
  `Speech.Duplex.OutputSegmenter` and `Speech.Duplex.BurstResponses` modules
  with the real OpenAI adapter so the default suite exercises the same room
  paths without a billable service. It reuses the Morse tone codec:
  - Caller tone is decoded into text and grouped into inferred turns.
  - Output is a continuous, clock-paced stream: leading silence, the Morse
    reply, then trailing silence. The energy gate splits it into bursts; each
    audible burst is announced as its own provider-initiated response through
    `:response_started` and admitted by the room, so the provider never needs to
    know where a reply ends.
  - It yields its own reply when it decodes caller tone during output.
  - Caller text `TOOL <name> <json>` raises a delegated tool call whose result
    appends a reply to the same output timeline.

  The provider owns its clock. By default (`clock: :realtime`) it records a
  monotonic origin and schedules its own 20 ms ticks, emitting the frames that
  are due with bounded catch-up; `advance/2` is rejected. A compiled room and
  the load lane run the real-time clock, so the provider speaks without
  external pacing.
  Test options (credential-free local provider only; never used by the
  GPT-Live adapter):

  - `clock: :manual` disables the timer and makes `advance/2` the only clock, so
    tests can drive deterministic audio time without sleeps.
  - `yield?: false` keeps a reply open when caller tone arrives, so a barge-in
    test can observe caller onset while output stays active. GPT-Live always
    decides for itself whether to yield.
  - `scripted_closes?: true` enables `script_close/2` to simulate one `:expired`
    or `:connection_lost` close. It reseeds only the room-published history and
    resumes a dropped burst or unanswered caller turn under the manual clock.
  """

  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder}

  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.{
    Clock,
    Hold,
    Output,
    Opening,
    Profile,
    ReplyFlow,
    ScriptedReseed,
    ToolReply,
    Transcript
  }

  import Vxpipe.CallEngine.Provider.MorseCodeDuplex.SegmentStore,
    only: [
      find_segment_by_turn: 2,
      find_segment_by_output: 2,
      put_segment: 3,
      delete_segment: 2,
      new_segment: 1,
      drain_all: 1
    ]

  alias Vxpipe.CallEngine.Speech.Duplex.{
    BurstResponses,
    OutputSegmenter,
    PublishedHistory,
    TurnInference
  }

  alias Vxpipe.CallEngine.Speech.{Channel, Event}

  @default_input_gap_ms 800
  @frame_ms 20
  @leading_silence_frames 10
  @trailing_silence_frames 60

  @impl true
  def configure(options), do: Profile.configure(options)

  @impl true
  def start_link(options),
    do: Vxpipe.CallEngine.Speech.STSProvider.start_link(__MODULE__, options)

  @impl true
  def push_audio(_pid, _audio), do: {:error, :unsupported_operation}

  @impl true
  def push_text(_pid, _reference, _text), do: {:error, :unsupported_operation}

  @impl true
  def submit_input(pid, context, operation) when is_reference(context),
    do: GenServer.call(pid, {:submit_input, context, operation}, 5_000)

  @impl true
  def input_activity(_pid, boundary) when boundary in [:started, :ended],
    do: {:error, :unsupported_operation}

  @impl true
  def input_quiescent?(pid), do: GenServer.call(pid, :input_quiescent?, 1_000)

  @impl true
  def set_input_hold(pid, held?) when is_boolean(held?),
    do: GenServer.call(pid, {:set_input_hold, held?}, 5_000)

  @impl true
  def append_history(pid, entry), do: GenServer.call(pid, {:append_history, entry}, 5_000)

  @impl true
  def interrupt(pid, turn_ref) when is_reference(turn_ref),
    do: GenServer.call(pid, {:interrupt, turn_ref}, 5_000)

  @impl true
  def send_tool_result(pid, call_ref, result),
    do: GenServer.call(pid, {:tool_result, call_ref, result}, 5_000)

  @impl true
  def close(pid) do
    GenServer.call(pid, :close, 5_000)
  catch
    :exit, {:noproc, _call} -> :ok
    :exit, {:normal, _call} -> :ok
  end

  @doc "Emit the next `ms` of audio-time output under the `clock: :manual` test mode."
  def advance(pid, ms) when is_integer(ms) and ms > 0,
    do: GenServer.call(pid, {:advance, ms}, 5_000)

  @doc "Simulate an expiry or connection loss in the local scripted-close test mode."
  def script_close(pid, reason) when reason in [:expired, :connection_lost],
    do: GenServer.call(pid, {:script_close, reason}, 5_000)

  @impl true
  def init(options) do
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = Keyword.fetch!(options, :channel)
    allocation = Keyword.fetch!(options, :allocation)

    with {:ok, config} <-
           descriptor.settings
           |> Map.drop([:yield?, :clock, :scripted_closes?])
           |> Map.to_list()
           |> Config.new(),
         {:ok, decoder} <- Decoder.new(config),
         {:ok, inference} <- TurnInference.new(gap_ms: @default_input_gap_ms),
         {:ok, segmenter} <- OutputSegmenter.new(Profile.segmenter_options(config)),
         {:ok, bursts} <- BurstResponses.new(),
         :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: descriptor.readiness) do
      clock = Map.get(descriptor.settings, :clock, :realtime)

      state = %{
        channel: channel,
        consumer: allocation.consumer,
        descriptor: descriptor,
        config: config,
        decoder: decoder,
        inference: inference,
        segmenter: segmenter,
        bursts: bursts,
        segments: %{},
        frame_bytes: div(config.sample_rate * @frame_ms, 1_000) * 2,
        input_ms: 0,
        timeline:
          Output.new(
            silence_bytes(config, @leading_silence_frames),
            silence_bytes(config, @trailing_silence_frames)
          ),
        last_partial: "",
        last_fragment_end_ms: nil,
        yield?: Map.get(descriptor.settings, :yield?, true),
        scripted_closes?: Map.get(descriptor.settings, :scripted_closes?, false),
        reseed_attempted?: false,
        pending_reseed: nil,
        unanswered?: false,
        clock: clock,
        clock_origin_ms: System.monotonic_time(:millisecond),
        emitted_frames: 0,
        clock_generation: make_ref(),
        clock_timer: nil,
        late_clocks: 0,
        pending_tools: %{},
        held?: false,
        hold_log: [],
        held_tool_replies: [],
        history: PublishedHistory.new()
      }

      if clock == :realtime, do: {:ok, schedule_tick(state)}, else: {:ok, state}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

  defp schedule_tick(state) do
    %{state | clock_timer: Process.send_after(self(), {:tick, state.clock_generation}, @frame_ms)}
  end

  defp cancel_clock(%{clock_timer: nil}), do: :ok
  defp cancel_clock(%{clock_timer: timer}), do: Process.cancel_timer(timer)

  @impl true
  def handle_call({:submit_input, _context, {:audio, _audio}}, _from, %{held?: true} = state),
    do: {:reply, :ok, state}

  def handle_call({:submit_input, context, {:audio, audio}}, _from, state)
      when is_binary(audio) do
    {bursts, []} = BurstResponses.input_accepted(state.bursts, context)
    decode_audio(%{state | bursts: bursts}, audio)
  end

  def handle_call({:submit_input, context, {:text, reference, text}}, _from, state)
      when is_reference(reference) and is_binary(text) do
    {bursts, []} = BurstResponses.input_accepted(state.bursts, context)
    state = %{state | bursts: bursts}

    with :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :locally_measured
           ),
         {:ok, state} <- publish_text_turn(state, text) do
      {:reply, :ok, state}
    else
      {:error, reason} -> {:stop, {:shutdown, reason}, {:error, reason}, state}
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:submit_input, _context, {:activity, _boundary}}, _from, state),
    do: {:reply, {:error, :unsupported_operation}, state}

  def handle_call({:submit_input, context, {:opening, reference, opening}}, _from, state),
    do: Opening.start(state, context, reference, opening)

  def handle_call({:submit_input, _context, _operation}, _from, state),
    do: {:reply, {:error, :unsupported_operation}, state}

  def handle_call(:input_quiescent?, _from, state) do
    quiescent? =
      Output.idle?(state.timeline) and state.segments == %{} and state.pending_tools == %{}

    {:reply, quiescent?, state}
  end

  def handle_call({:append_history, {role, text} = entry}, _from, state)
      when role in [:caller, :agent] and is_binary(text) and byte_size(text) > 0,
      do: {:reply, :ok, %{state | history: PublishedHistory.append(state.history, entry)}}

  def handle_call({:append_history, _entry}, _from, state),
    do: {:reply, {:error, :invalid_history}, state}

  def handle_call({:script_close, reason}, from, %{scripted_closes?: true} = state)
      when reason in [:expired, :connection_lost] do
    script_close_session(state, reason, from)
  end

  def handle_call({:script_close, _reason}, _from, state),
    do: {:reply, {:error, :unsupported_operation}, state}

  def handle_call({:set_input_hold, true}, _from, %{held?: false} = state),
    do: Hold.set(state, true)

  def handle_call({:set_input_hold, false}, _from, %{held?: true} = state),
    do: Hold.set(state, false)

  def handle_call({:set_input_hold, held?}, _from, %{held?: held?} = state),
    do: {:reply, :ok, state}

  def handle_call({:interrupt, turn_ref}, _from, state) when is_reference(turn_ref) do
    case find_segment_by_turn(state, turn_ref) do
      {:ok, seg_ref, segment} ->
        segment = %{segment | yielded?: true, queue: [], queue_bytes: 0}
        state = put_segment(state, seg_ref, segment)
        {:reply, :ok, drain_all(state)}

      :error ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  def handle_call({:tool_result, call_ref, result}, _from, state) when is_reference(call_ref) do
    case Map.fetch(state.pending_tools, call_ref) do
      {:ok, _tool} ->
        state = %{state | pending_tools: Map.delete(state.pending_tools, call_ref)}

        case ToolReply.publish(state, result) do
          {:ok, state} -> {:reply, :ok, state}
          {:error, reason} -> {:stop, {:shutdown, reason}, {:error, reason}, state}
        end

      :error ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  def handle_call({:advance, _ms}, _from, %{clock: :realtime} = state),
    do: {:reply, {:error, :unsupported_operation}, state}

  def handle_call({:advance, ms}, _from, state) when is_integer(ms) and ms > 0 do
    case advance_clock(state, ms) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, :buffer_overflow, state} ->
        {:stop, {:shutdown, :buffer_overflow}, {:error, :buffer_overflow}, state}

      {:error, reason, state} ->
        {:stop, {:shutdown, reason}, {:error, reason}, state}
    end
  end

  def handle_call(:close, _from, state) do
    _ = cancel_clock(state)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:tick, generation}, %{clock: :realtime, clock_generation: generation} = state) do
    now = System.monotonic_time(:millisecond)

    {due, origin, emitted, stalled?} =
      Clock.frames_due(state.clock_origin_ms, now, state.emitted_frames)

    state = %{
      state
      | clock_origin_ms: origin,
        emitted_frames: emitted,
        late_clocks: state.late_clocks + if(stalled?, do: 1, else: 0)
    }

    case emit_frames(state, due) do
      {:ok, state} -> {:noreply, schedule_tick(state)}
      {:error, :buffer_overflow, state} -> {:stop, {:shutdown, :buffer_overflow}, state}
      {:error, reason, state} -> {:stop, {:shutdown, reason}, state}
    end
  end

  def handle_info({:vxpipe_speech_output, _channel, turn_ref, output_ref}, state)
      when is_reference(turn_ref) and is_reference(output_ref) do
    handle_admit(state, turn_ref, output_ref)
  end

  def handle_info(
        {:vxpipe_speech_response_discard, _channel, turn_ref},
        state
      )
      when is_reference(turn_ref) do
    handle_discard(state, turn_ref)
  end

  def handle_info({:vxpipe_speech_credit, _channel, output_ref, credit, :ok}, state) do
    case find_segment_by_output(state, output_ref) do
      {:ok, seg_ref, %{awaiting: ^credit} = segment} ->
        state = put_segment(state, seg_ref, %{segment | awaiting: nil})
        {:noreply, drain_all(state)}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:vxpipe_sts_reseed_history_ready, consumer, reference},
        %{consumer: consumer, pending_reseed: %{reference: reference} = pending} = state
      ),
      do: ScriptedReseed.confirm(state, pending)

  def handle_info(
        {:reseed_barrier_timeout, reference},
        %{pending_reseed: %{reference: reference} = pending} = state
      ),
      do: ScriptedReseed.timeout(state, pending)

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :morse_code_duplex_session)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp script_close_session(%{pending_reseed: pending} = state, _reason, _from)
       when not is_nil(pending),
       do: {:reply, {:error, :busy}, state}

  defp script_close_session(%{reseed_attempted?: true} = state, _reason, _from),
    do: {:stop, {:shutdown, :reseed_failed}, {:error, :reseed_failed}, state}

  defp script_close_session(state, reason, from) do
    resume? = OutputSegmenter.burst?(state.segmenter) or state.unanswered?
    {segmenter, events} = OutputSegmenter.finish(state.segmenter)

    with {:ok, state} <- apply_segmenter_events(events, %{state | segmenter: segmenter}) do
      ScriptedReseed.begin(state, from, reason, resume?)
    else
      _failure -> {:stop, {:shutdown, :reseed_failed}, {:error, :reseed_failed}, state}
    end
  end

  # Input ------------------------------------------------------------------

  defp decode_audio(state, audio) do
    state = %{state | input_ms: state.input_ms + duration_ms(state.config, byte_size(audio))}

    case Decoder.push(state.decoder, audio) do
      {:ok, decoder, events} ->
        case apply_decoder_events(events, %{state | decoder: decoder}) do
          {:ok, state} -> {:reply, :ok, state}
          {:error, reason} -> {:stop, {:shutdown, reason}, {:error, reason}, state}
        end

      {:error, _reason} ->
        {:ok, decoder} = Decoder.new(state.config)

        {:stop, {:shutdown, :session_failed}, {:error, :session_failed},
         %{state | decoder: decoder}}
    end
  end

  defp apply_decoder_events(events, state) do
    Enum.reduce_while(events, {:ok, state}, fn event, {:ok, state} ->
      case apply_decoder_event(event, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp apply_decoder_event(:started, %{yield?: false} = state), do: {:ok, state}
  defp apply_decoder_event(:started, state), do: {:ok, ReplyFlow.yield_current(state)}

  defp apply_decoder_event({:partial, text}, state), do: feed_fragment(state, text)

  defp apply_decoder_event({:final, text}, state) do
    with {:ok, state} <- feed_fragment(state, text),
         {:ok, state, _close_events} <- close_input_turn(state) do
      ToolReply.follow_up(state, text)
    end
  end

  # GPT-Live sends input fragments while the caller speaks; feed each decoded
  # delta so caller onset reaches the room before the reply has finished. The
  # fragments are contiguous audio-time slices, so the caller turn is grouped by
  # the utterance close rather than split by sparse fragment timing.
  defp feed_fragment(state, full_text) do
    delta = delta_since(state.last_partial, full_text)
    state = %{state | last_partial: full_text}

    if delta == "" do
      {:ok, state}
    else
      end_ms = state.input_ms
      start_ms = min(state.last_fragment_end_ms || end_ms, end_ms)
      fragment = %{text: delta, start_ms: start_ms, end_ms: end_ms}
      {inference, events} = TurnInference.input_fragment(state.inference, fragment)

      state = %{
        state
        | inference: inference,
          last_fragment_end_ms: end_ms
      }

      with :ok <- emit_events(events, state), do: {:ok, state}
    end
  end

  defp close_input_turn(state) do
    {inference, events} = TurnInference.audio_pushed(state.inference, @default_input_gap_ms)

    state = %{
      state
      | inference: inference,
        last_partial: "",
        last_fragment_end_ms: nil
    }

    with :ok <- emit_events(events, state) do
      unanswered? = Enum.any?(events, fn {kind, _fields} -> kind == :turn_ended end)
      {:ok, %{state | unanswered?: state.unanswered? or unanswered?}, events}
    end
  end

  defp delta_since("", full), do: full

  defp delta_since(last, full) do
    if String.starts_with?(full, last) do
      binary_part(full, byte_size(last), byte_size(full) - byte_size(last))
    else
      full
    end
  end

  defp publish_text_turn(state, text) do
    turn_ref = make_ref()
    events = [{:input_transcript, [turn_ref: turn_ref, text: text, final: true]}]

    with :ok <- emit_events(events, state),
         {:ok, state} <- maybe_emit_tool(state, turn_ref, text),
         :ok <-
           Event.emit(state.channel, :turn_ended,
             turn_ref: turn_ref,
             text: text,
             endpointing: :inferred_gap
           ) do
      ToolReply.follow_up(%{state | unanswered?: true}, text)
    end
  end

  defp emit_events(events, state) do
    Enum.reduce_while(events, :ok, fn {kind, fields}, :ok ->
      case Event.emit(state.channel, kind, fields) do
        :ok -> {:cont, :ok}
        _failure -> {:halt, {:error, :session_failed}}
      end
    end)
  end

  defp maybe_emit_tool(state, turn_ref, text) do
    case ToolReply.trigger(text) do
      {:tool, name, arguments} ->
        call_ref = make_ref()

        case Event.emit(state.channel, :tool_call,
               call_ref: call_ref,
               turn_ref: turn_ref,
               tool_name: name,
               arguments: arguments,
               response_context: BurstResponses.latest_context(state.bursts)
             ) do
          :ok ->
            {:ok,
             %{
               state
               | pending_tools:
                   Map.put(state.pending_tools, call_ref, %{turn_ref: turn_ref, name: name})
             }}

          _failure ->
            {:error, :session_failed}
        end

      :not_a_tool ->
        {:ok, state}
    end
  end

  # Output -----------------------------------------------------------------

  defp advance_clock(state, ms) do
    frames = max(div(ms, @frame_ms), 1)
    emit_frames(state, frames)
  end

  defp emit_frames(state, 0), do: {:ok, state}

  defp emit_frames(state, frames) do
    Enum.reduce_while(1..frames, {:ok, state}, fn _, {:ok, state} ->
      case emit_frame(state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, :buffer_overflow, state} -> {:halt, {:error, :buffer_overflow, state}}
        {:error, reason, state} -> {:halt, {:error, reason, state}}
      end
    end)
  end

  defp emit_frame(state) do
    {frame, due, state} = ReplyFlow.next_frame(state)
    frame_start_ms = state.segmenter.produced_ms

    case OutputSegmenter.push_pcm(state.segmenter, frame) do
      {:error, :buffer_overflow, segmenter} ->
        {:error, :buffer_overflow, %{state | segmenter: segmenter}}

      {segmenter, events} ->
        state = %{state | segmenter: segmenter}

        case apply_segmenter_events(events, state) do
          {:ok, state} ->
            case emit_due_fragments(due, frame_start_ms, state) do
              {:ok, state} -> {:ok, state |> ReplyFlow.advance() |> drain_all()}
              {:error, reason, state} -> {:error, reason, state}
            end

          {:error, :buffer_overflow, state} ->
            {:error, :buffer_overflow, state}

          {:error, reason, state} ->
            {:error, reason, state}
        end
    end
  end

  defp emit_due_fragments(due, frame_start_ms, state) do
    due
    |> Transcript.due_fragments(frame_start_ms, state.config.sample_rate)
    |> Enum.reduce_while({:ok, state}, fn fragment, {:ok, state} ->
      {segmenter, events} = OutputSegmenter.fragment(state.segmenter, fragment)

      case apply_segmenter_events(events, %{state | segmenter: segmenter}) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason, state} -> {:halt, {:error, reason, state}}
      end
    end)
  end

  defp apply_segmenter_events(events, state) do
    Enum.reduce_while(events, {:ok, state}, fn event, {:ok, state} ->
      case apply_segmenter_event(event, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason, state} -> {:halt, {:error, reason, state}}
      end
    end)
  end

  defp apply_segmenter_event({:open, seg_ref}, state) do
    case BurstResponses.burst_opened(state.bursts, seg_ref) do
      {:error, :pending_response_overflow} ->
        {:error, :pending_response_overflow, state}

      {bursts, [{:drop_segment, ^seg_ref}]} ->
        {segmenter, _events} = OutputSegmenter.finish(state.segmenter)
        {:ok, %{state | bursts: bursts, segmenter: segmenter}}

      {bursts, [{:announce, turn_ref, index, context}]} ->
        case Event.emit(state.channel, :response_started,
               turn_ref: turn_ref,
               response_index: index,
               response_context: context
             ) do
          :ok ->
            segment = new_segment(turn_ref)

            {:ok,
             %{
               state
               | bursts: bursts,
                 segments: Map.put(state.segments, seg_ref, segment),
                 unanswered?: false
             }}

          _failure ->
            {:error, :session_failed, state}
        end
    end
  end

  defp apply_segmenter_event({:audio, seg_ref, pcm}, state) do
    case Map.fetch(state.segments, seg_ref) do
      {:ok, %{yielded?: true}} ->
        {:ok, state}

      {:ok, segment} ->
        enqueue_segment(state, seg_ref, segment, pcm)

      :error ->
        {:ok, state}
    end
  end

  defp apply_segmenter_event({:close, seg_ref}, state) do
    {bursts, actions} = BurstResponses.burst_closed(state.bursts, seg_ref)
    state = %{state | bursts: bursts}

    Enum.reduce_while(actions, {:ok, state}, fn
      {:complete, turn_ref, _output_ref}, {:ok, state} ->
        case find_segment_by_turn(state, turn_ref) do
          {:ok, seg_ref, segment} ->
            {:cont,
             {:ok, put_segment(state, seg_ref, %{segment | closed?: true, completed?: true})}}

          :error ->
            {:cont, {:ok, state}}
        end

      _action, acc ->
        {:cont, acc}
    end)
  end

  defp apply_segmenter_event({:transcript, seg_ref, text, start_ms, end_ms}, state) do
    Transcript.accept(state, seg_ref, text, start_ms, end_ms)
  end

  defp apply_segmenter_event(_event, state), do: {:ok, state}

  defp enqueue_segment(state, seg_ref, segment, pcm) do
    bytes = segment.queue_bytes + byte_size(pcm)
    segment = %{segment | queue: segment.queue ++ [pcm], queue_bytes: bytes}
    state = put_segment(state, seg_ref, segment)

    if bytes > buffer_bytes(state) do
      {:error, :buffer_overflow, state}
    else
      {:ok, state}
    end
  end

  defp handle_admit(state, turn_ref, output_ref) do
    {bursts, actions} = BurstResponses.admitted(state.bursts, turn_ref, output_ref)
    state = %{state | bursts: bursts}

    case apply_admit_actions(actions, state) do
      {:ok, state} -> {:noreply, drain_all(state)}
      {:error, reason, state} -> {:stop, {:shutdown, reason}, state}
    end
  end

  defp apply_admit_actions(actions, state) do
    Enum.reduce_while(actions, {:ok, state}, fn action, {:ok, state} ->
      case apply_admit_action(action, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason, state} -> {:halt, {:error, reason, state}}
      end
    end)
  end

  defp apply_admit_action({:admit_segment, seg_ref, output_ref}, state) do
    {segmenter, events} = OutputSegmenter.admitted(state.segmenter, seg_ref)
    state = %{state | segmenter: segmenter}

    state =
      case Map.fetch(state.segments, seg_ref) do
        {:ok, segment} -> put_segment(state, seg_ref, %{segment | output_ref: output_ref})
        :error -> state
      end

    with {:ok, state} <- apply_segmenter_events(events, state),
         {:ok, state} <- Transcript.admitted(state, seg_ref) do
      {:ok, state}
    else
      {:error, reason, state} -> {:error, reason, state}
    end
  end

  defp apply_admit_action({:complete, turn_ref, _output_ref}, state) do
    case find_segment_by_turn(state, turn_ref) do
      {:ok, seg_ref, segment} ->
        {:ok, put_segment(state, seg_ref, %{segment | closed?: true, completed?: true})}

      :error ->
        {:ok, state}
    end
  end

  defp apply_admit_action({:complete_empty, turn_ref, output_ref}, state) do
    case find_segment_by_turn(state, turn_ref) do
      {:ok, seg_ref, _segment} ->
        {segmenter, _events} = OutputSegmenter.finish(state.segmenter)
        state = %{state | segmenter: segmenter} |> delete_segment(seg_ref)
        complete_empty(state, turn_ref, output_ref)

      :error ->
        {:ok, state}
    end
  end

  defp apply_admit_action(_action, state), do: {:ok, state}

  defp complete_empty(state, turn_ref, output_ref) do
    with :ok <- Event.emit(state.channel, :interrupted, turn_ref: turn_ref),
         :ok <-
           Event.emit(state.channel, :output_completed,
             turn_ref: turn_ref,
             request_ref: output_ref
           ) do
      {:ok, state}
    else
      _failure -> {:error, :session_failed, state}
    end
  end

  defp handle_discard(state, turn_ref) do
    {bursts, actions} = BurstResponses.discarded(state.bursts, turn_ref)
    state = %{state | bursts: bursts}

    state =
      Enum.reduce(actions, state, fn {:drop_segment, seg_ref}, state ->
        {segmenter, _events} = OutputSegmenter.finish(state.segmenter)
        state |> Map.put(:segmenter, segmenter) |> delete_segment(seg_ref)
      end)

    {:noreply, drain_all(state)}
  end

  # Helpers ----------------------------------------------------------------

  defp silence_bytes(config, frames),
    do: :binary.copy(<<0, 0>>, div(config.sample_rate * @frame_ms, 1_000) * frames * 2)

  defp buffer_bytes(state), do: div(2_000 * state.config.sample_rate, 1_000) * 2

  defp duration_ms(config, bytes), do: div(bytes * 1_000, config.sample_rate * 2)
end
