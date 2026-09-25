defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.Session do
  @moduledoc """
  Credential-free local provider that behaves like GPT-Live.

  It shares the provider-neutral `Speech.Duplex.TurnInference` and
  `Speech.Duplex.OutputSegmenter` modules with the real OpenAI adapter so the
  default suite exercises the same room paths without a billable service. It
  reuses the Morse tone codec:

  - Caller tone is decoded into text and grouped into inferred turns.
  - Output is a continuous, clock-paced stream: leading silence, the Morse
    reply, then trailing silence. Only the audio the output energy gate admits
    is forwarded, so silence between bursts is discarded.
  - It yields its own reply when it decodes caller tone during output.
  - Caller text `TOOL <name> <json>` raises a delegated tool call whose result
    reopens a reply.

  The provider owns its clock. By default (`clock: :realtime`) it records a
  monotonic origin and schedules its own 20 ms ticks, emitting the frames that
  are due with bounded catch-up; `advance/2` is rejected. A compiled room, the
  load lane and any other host run the real-time clock, so the provider speaks
  without external pacing.

  Test options (credential-free local provider only; never used by the GPT-Live
  adapter):

  - `clock: :manual` disables the timer and makes `advance/2` the only clock, so
    tests can drive deterministic audio time without sleeps.
  - `yield?: false` keeps a reply open when caller tone arrives, so a barge-in
    test can observe caller onset while output stays active. GPT-Live always
    decides for itself whether to yield.
  """

  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder, Encoder}
  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.{Clock, Profile, ToolReply}
  alias Vxpipe.CallEngine.Speech.Duplex.{OutputSegmenter, TurnInference}
  alias Vxpipe.CallEngine.Speech.{Channel, Event}

  @default_input_gap_ms 800
  @frame_ms 20
  @leading_silence_frames 10
  @trailing_silence_frames 60
  @maximum_queued_replies 16
  @maximum_yielded_pending 16

  @impl true
  def configure(options), do: Profile.configure(options)

  @impl true
  def start_link(options),
    do: Vxpipe.CallEngine.Speech.STSProvider.start_link(__MODULE__, options)

  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:push_audio, audio}, 5_000)

  @impl true
  def push_text(pid, reference, text) when is_reference(reference) and is_binary(text),
    do: GenServer.call(pid, {:push_text, reference, text}, 5_000)

  @impl true
  def input_activity(_pid, boundary) when boundary in [:started, :ended],
    do: {:error, :unsupported_operation}

  @impl true
  def input_quiescent?(pid), do: GenServer.call(pid, :input_quiescent?, 1_000)

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

  @impl true
  def init(options) do
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = Keyword.fetch!(options, :channel)

    with {:ok, config} <-
           descriptor.settings
           |> Map.drop([:yield?, :clock])
           |> Map.to_list()
           |> Config.new(),
         {:ok, decoder} <- Decoder.new(config),
         {:ok, inference} <- TurnInference.new(gap_ms: @default_input_gap_ms),
         {:ok, segmenter} <- OutputSegmenter.new(Profile.segmenter_options(config)),
         :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: descriptor.readiness) do
      clock = Map.get(descriptor.settings, :clock, :realtime)

      state = %{
        channel: channel,
        descriptor: descriptor,
        config: config,
        decoder: decoder,
        inference: inference,
        segmenter: segmenter,
        frame_bytes: div(config.sample_rate * @frame_ms, 1_000) * 2,
        input_ms: 0,
        output: nil,
        queued_replies: [],
        yielded_pending: [],
        last_partial: "",
        last_fragment_end_ms: nil,
        yield_deferred?: false,
        yield?: Map.get(descriptor.settings, :yield?, true),
        clock: clock,
        clock_origin_ms: System.monotonic_time(:millisecond),
        emitted_frames: 0,
        clock_generation: make_ref(),
        clock_timer: nil,
        late_clocks: 0,
        pending_tools: %{}
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
  def handle_call({:push_audio, audio}, _from, state) when is_binary(audio),
    do: decode_audio(state, audio)

  def handle_call({:push_text, reference, text}, _from, state)
      when is_reference(reference) and is_binary(text) do
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

  def handle_call(:input_quiescent?, _from, state) do
    quiescent? =
      is_nil(state.output) and state.queued_replies == [] and state.pending_tools == %{}

    {:reply, quiescent?, state}
  end

  def handle_call({:interrupt, turn_ref}, _from, state) when is_reference(turn_ref) do
    cond do
      match?(%{turn_ref: ^turn_ref}, state.output) ->
        {:reply, :ok, self_yield(state, defer: false)}

      Enum.any?(state.queued_replies, &(&1.turn_ref == turn_ref)) ->
        queued = Enum.reject(state.queued_replies, &(&1.turn_ref == turn_ref))
        {:reply, :ok, %{state | queued_replies: queued}}

      turn_ref in state.yielded_pending ->
        {:reply, :ok, %{state | yielded_pending: List.delete(state.yielded_pending, turn_ref)}}

      true ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  def handle_call({:tool_result, call_ref, result}, _from, state) when is_reference(call_ref) do
    case Map.fetch(state.pending_tools, call_ref) do
      {:ok, _tool} ->
        state = %{state | pending_tools: Map.delete(state.pending_tools, call_ref)}

        case publish_tool_reply(state, result) do
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
    end
  end

  def handle_info({:vxpipe_speech_output, _channel, turn_ref, output_ref}, state)
      when is_reference(turn_ref) and is_reference(output_ref) do
    handle_admit(state, turn_ref, output_ref)
  end

  def handle_info({:vxpipe_speech_credit, _channel, output_ref, credit, :ok}, state) do
    case state.output do
      %{output_ref: ^output_ref, awaiting: ^credit} = output ->
        state = %{state | output: %{output | awaiting: nil}}
        {:noreply, state |> drain_submit() |> then(&finish_if_ready(&1))}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :morse_code_duplex_session)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
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
  defp apply_decoder_event(:started, state), do: {:ok, self_yield(state, defer: true)}

  defp apply_decoder_event({:partial, text}, state), do: feed_fragment(state, text)

  defp apply_decoder_event({:final, text}, state) do
    with {:ok, state} <- feed_fragment(state, text),
         {:ok, state, close_events} <- close_input_turn(state) do
      case last_turn_ref(close_events) do
        {:ok, turn_ref} -> follow_up(state, turn_ref, text)
        {:error, _reason} = error -> error
      end
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
          yield_deferred?: false,
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
        last_fragment_end_ms: nil,
        yield_deferred?: false
    }

    with :ok <- emit_events(events, state), do: {:ok, state, events}
  end

  defp delta_since("", full), do: full

  defp delta_since(last, full) do
    if String.starts_with?(full, last) do
      binary_part(full, byte_size(last), byte_size(full) - byte_size(last))
    else
      full
    end
  end

  defp last_turn_ref(events) do
    case Enum.find(events, fn {kind, _fields} -> kind == :turn_ended end) do
      {:turn_ended, fields} -> {:ok, Keyword.fetch!(fields, :turn_ref)}
      nil -> {:error, :session_failed}
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
      follow_up(state, turn_ref, text)
    end
  end

  defp publish_tool_reply(state, result) do
    with {:ok, text} <- ToolReply.text(state.config, result),
         {:ok, pcm} <- Encoder.encode(state.config, text) do
      turn_ref = make_ref()

      case Event.emit(state.channel, :turn_ended,
             turn_ref: turn_ref,
             text: text,
             endpointing: :inferred_gap
           ) do
        :ok -> enqueue_reply(state, %{turn_ref: turn_ref, text: text, pcm: pcm, output_ref: nil})
        _failure -> {:error, :session_failed}
      end
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

  defp follow_up(state, turn_ref, text) do
    case ToolReply.trigger(text) do
      {:tool, _name, _arguments} ->
        {:ok, state}

      :not_a_tool ->
        start_reply(state, turn_ref, ToolReply.reply(state.config, text))
    end
  end

  defp maybe_emit_tool(state, turn_ref, text) do
    case ToolReply.trigger(text) do
      {:tool, name, arguments} ->
        call_ref = make_ref()

        case Event.emit(state.channel, :tool_call,
               call_ref: call_ref,
               turn_ref: turn_ref,
               tool_name: name,
               arguments: arguments
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
      end
    end)
  end

  defp emit_frame(state) do
    {frame, state} = next_frame(state)

    case OutputSegmenter.push_pcm(state.segmenter, frame) do
      {:error, :buffer_overflow, segmenter} ->
        {:error, :buffer_overflow, %{state | segmenter: segmenter}}

      {segmenter, events} ->
        state = %{state | segmenter: segmenter}

        case apply_segmenter_events(events, state) do
          {:ok, state} -> {:ok, state |> drain_submit() |> then(&finish_if_ready(&1))}
          {:error, :buffer_overflow, state} -> {:error, :buffer_overflow, state}
        end
    end
  end

  defp next_frame(%{output: nil} = state), do: {silence_frame(state), state}

  defp next_frame(%{output: output} = state) do
    if output.cursor < byte_size(output.stream) do
      size = min(state.frame_bytes, byte_size(output.stream) - output.cursor)
      frame = binary_part(output.stream, output.cursor, size)
      {frame, %{state | output: %{output | cursor: output.cursor + size}}}
    else
      {silence_frame(state), state}
    end
  end

  defp apply_segmenter_events(events, state) do
    Enum.reduce_while(events, {:ok, state}, fn
      {:open, seg_ref}, {:ok, state} ->
        case open_burst(%{state | output: put_seg_ref(state.output, seg_ref)}, seg_ref) do
          {:ok, state} -> {:cont, {:ok, state}}
          {:error, _reason} = error -> {:halt, error}
        end

      {:audio, _seg_ref, pcm}, {:ok, state} ->
        case enqueue_submit(state, pcm) do
          {:ok, state} -> {:cont, {:ok, state}}
          {:error, :buffer_overflow, state} -> {:halt, {:error, :buffer_overflow, state}}
        end

      {:close, _seg_ref}, {:ok, state} ->
        {:cont, {:ok, mark_close(state)}}

      _event, acc ->
        {:cont, acc}
    end)
  end

  defp put_seg_ref(nil, _seg_ref), do: nil
  defp put_seg_ref(output, seg_ref), do: %{output | seg_ref: seg_ref}

  defp open_burst(%{output: nil} = state, _seg_ref) do
    {:ok, state}
  end

  defp open_burst(%{output: %{output_ref: nil}} = state, _seg_ref) do
    {:ok, state}
  end

  defp open_burst(%{output: output} = state, seg_ref) do
    # A later burst of the same reply continues the already-admitted output: its
    # buffered audio is flushed under the existing output reference, so silence
    # between bursts is dropped and the agent turn spans all its bursts.
    {segmenter, events} = OutputSegmenter.admitted(state.segmenter, seg_ref)
    state = %{state | segmenter: segmenter, output: %{output | seg_ref: seg_ref, admitted?: true}}

    case apply_segmenter_events(events, state) do
      {:ok, state} -> {:ok, state}
      {:error, :buffer_overflow, state} -> {:error, :buffer_overflow, state}
    end
  end

  defp mark_close(%{output: nil} = state), do: state

  defp mark_close(%{output: output} = state),
    do: %{state | output: %{output | close_pending?: true}}

  defp enqueue_submit(%{output: nil} = state, _pcm), do: {:ok, state}

  defp enqueue_submit(%{output: output} = state, pcm) do
    queued = output.queue ++ [pcm]
    bytes = output.queue_bytes + byte_size(pcm)

    if bytes > buffer_bytes(state) do
      {:error, :buffer_overflow, %{state | output: %{output | queue: queued, queue_bytes: bytes}}}
    else
      {:ok, %{state | output: %{output | queue: queued, queue_bytes: bytes}}}
    end
  end

  defp drain_submit(%{output: %{awaiting: nil} = output} = state)
       when output.output_ref != nil do
    case output.queue do
      [pcm | rest] ->
        case Channel.submit(state.channel, output.output_ref, pcm) do
          {:ok, credit} ->
            %{
              state
              | output: %{
                  output
                  | queue: rest,
                    queue_bytes: output.queue_bytes - byte_size(pcm),
                    awaiting: credit
                }
            }

          _failure ->
            %{state | output: %{output | queue: [], queue_bytes: 0, interrupted?: true}}
        end

      [] ->
        state
    end
  end

  defp drain_submit(state), do: state

  defp finish_if_ready(%{output: nil} = state), do: state

  defp finish_if_ready(%{output: output} = state) do
    cond do
      output.interrupted? and state.yield_deferred? ->
        state

      output.interrupted? and output.awaiting != nil ->
        state

      output.interrupted? and output.output_ref == nil ->
        start_queued(remember_yielded(%{state | output: nil}, output.turn_ref))

      output.interrupted? ->
        complete_output(state)

      output.cursor >= byte_size(output.stream) and output.close_pending? and output.queue == [] and
        output.awaiting == nil and output.admitted? ->
        complete_output(state)

      true ->
        state
    end
  end

  defp remember_yielded(state, turn_ref) do
    pending =
      if turn_ref in state.yielded_pending do
        state.yielded_pending
      else
        Enum.take([turn_ref | state.yielded_pending], @maximum_yielded_pending)
      end

    %{state | yielded_pending: pending}
  end

  defp handle_admit(state, turn_ref, output_ref) do
    cond do
      match?(%{turn_ref: ^turn_ref}, state.output) ->
        admit_current(state, turn_ref, output_ref)

      Enum.any?(state.queued_replies, &(&1.turn_ref == turn_ref)) ->
        queued =
          Enum.map(state.queued_replies, fn reply ->
            if reply.turn_ref == turn_ref, do: %{reply | output_ref: output_ref}, else: reply
          end)

        {:noreply, %{state | queued_replies: queued}}

      turn_ref in state.yielded_pending ->
        _ = Event.emit(state.channel, :interrupted, turn_ref: turn_ref)
        {:noreply, %{state | yielded_pending: List.delete(state.yielded_pending, turn_ref)}}

      true ->
        {:noreply, state}
    end
  end

  defp admit_current(state, _turn_ref, output_ref) do
    state = %{state | output: %{state.output | output_ref: output_ref}}

    state =
      case state.output.seg_ref do
        nil ->
          state

        seg_ref ->
          case open_burst(state, seg_ref) do
            {:ok, state} -> state
            {:error, :buffer_overflow, state} -> state
          end
      end

    state = state |> drain_submit() |> finish_if_ready()
    {:noreply, state}
  end

  defp start_reply(state, turn_ref, text) do
    with {:ok, pcm} <- Encoder.encode(state.config, text) do
      enqueue_reply(state, %{turn_ref: turn_ref, text: text, pcm: pcm, output_ref: nil})
    end
  end

  defp enqueue_reply(%{output: nil} = state, reply), do: {:ok, begin_output(state, reply)}

  defp enqueue_reply(state, reply) do
    if length(state.queued_replies) >= @maximum_queued_replies do
      {:error, :pending_reply_overflow}
    else
      {:ok, %{state | queued_replies: state.queued_replies ++ [reply]}}
    end
  end

  defp begin_output(state, reply) do
    stream =
      silence(state, @leading_silence_frames) <>
        reply.pcm <> silence(state, @trailing_silence_frames)

    output = %{
      turn_ref: reply.turn_ref,
      text: reply.text,
      output_ref: reply.output_ref,
      admitted?: false,
      stream: stream,
      cursor: 0,
      seg_ref: nil,
      close_pending?: false,
      awaiting: nil,
      queue: [],
      queue_bytes: 0,
      interrupted?: false
    }

    %{state | output: output}
  end

  defp start_queued(%{output: nil, queued_replies: [reply | rest]} = state) do
    state = begin_output(%{state | queued_replies: rest}, reply)

    if reply.output_ref do
      {:noreply, state} = admit_current(state, reply.turn_ref, reply.output_ref)
      state
    else
      state
    end
  end

  defp start_queued(state), do: state

  defp complete_output(state) do
    output = state.output

    _ =
      Event.emit(state.channel, :output_transcript,
        turn_ref: output.turn_ref,
        text: output.text,
        final: true
      )

    _ =
      Event.emit(state.channel, :output_completed,
        turn_ref: output.turn_ref,
        request_ref: output.output_ref
      )

    start_queued(%{state | output: nil})
  end

  defp self_yield(%{output: nil} = state, _opts), do: state

  defp self_yield(%{output: output} = state, opts) do
    {segmenter, _events} = OutputSegmenter.finish(state.segmenter)

    state = %{
      state
      | segmenter: segmenter,
        yield_deferred?: Keyword.get(opts, :defer, false),
        output: %{
          output
          | interrupted?: true,
            seg_ref: nil,
            cursor: byte_size(output.stream),
            close_pending?: true,
            queue: [],
            queue_bytes: 0
        }
    }

    finish_if_ready(state)
  end

  # Pricing helpers --------------------------------------------------------

  defp silence_frame(state),
    do: :binary.copy(<<0, 0>>, div(state.config.sample_rate * @frame_ms, 1_000))

  defp silence(state, frames), do: :binary.copy(silence_frame(state), frames)

  defp buffer_bytes(state), do: div(2_000 * state.config.sample_rate, 1_000) * 2

  defp duration_ms(config, bytes), do: div(bytes * 1_000, config.sample_rate * 2)
end
