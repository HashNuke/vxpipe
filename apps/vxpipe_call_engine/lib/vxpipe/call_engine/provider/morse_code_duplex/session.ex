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
  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.Clock
  alias Vxpipe.CallEngine.Speech.Duplex.{OutputSegmenter, TurnInference}
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event}

  @reply_prefix "RECEIVED "
  @default_input_gap_ms 800
  @frame_ms 20
  @leading_silence_frames 10
  @trailing_silence_frames 60

  @impl true
  def configure(options) do
    allowed = Config.option_keys() ++ [:output_transcript, :yield?, :clock]

    with true <- is_list(options) and Keyword.keyword?(options),
         true <- length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))),
         true <- Enum.all?(Keyword.keys(options), &(&1 in allowed)),
         {output_transcript, rest} = Keyword.pop(options, :output_transcript, true),
         true <- is_boolean(output_transcript),
         {yield?, rest} = Keyword.pop(rest, :yield?, true),
         true <- is_boolean(yield?),
         {clock, rest} = Keyword.pop(rest, :clock, :realtime),
         true <- clock in [:realtime, :manual],
         {:ok, config} <- Config.new(rest) do
      Descriptor.new(
        kind: :sts,
        settings:
          config
          |> Map.from_struct()
          |> Map.put(:yield?, yield?)
          |> Map.put(:clock, clock),
        input_format: format(config),
        format: format(config),
        usage_identity: %{
          provider: :morse_code_duplex,
          model: :morse_code,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: :inferred_gap,
        speech_start?: true,
        turn_control: "provider",
        turn_control_supported: ["provider"],
        input_transcript?: true,
        output_transcript?: output_transcript,
        output_settlement: :transcript_end,
        history_reconciliation?: false,
        output_shape: :continuous,
        barge_in: :provider,
        continuity: :history_reseed,
        tool_cancellation?: false,
        hold: :mute
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  defp format(config) do
    %{
      encoding: :linear16,
      container: :raw,
      sample_rate: config.sample_rate,
      channels: 1,
      byte_order: :little,
      signed?: true
    }
  end

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
         {:ok, segmenter} <- OutputSegmenter.new(segmenter_options(config)),
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
        queued_reply: nil,
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

  defp segmenter_options(config), do: [sample_rate: config.sample_rate]

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
      _failure -> {:reply, {:error, :session_failed}, state}
    end
  end

  def handle_call(:input_quiescent?, _from, state) do
    quiescent? =
      is_nil(state.output) and is_nil(state.queued_reply) and state.pending_tools == %{}

    {:reply, quiescent?, state}
  end

  def handle_call({:interrupt, turn_ref}, _from, state) when is_reference(turn_ref) do
    case state.output do
      %{turn_ref: ^turn_ref} -> {:reply, :ok, self_yield(state)}
      _other -> {:reply, {:error, :stale_request}, state}
    end
  end

  def handle_call({:tool_result, call_ref, result}, _from, state) when is_reference(call_ref) do
    case Map.fetch(state.pending_tools, call_ref) do
      {:ok, _tool} ->
        state = %{state | pending_tools: Map.delete(state.pending_tools, call_ref)}
        reply = @reply_prefix <> summarize(result)
        {:reply, :ok, publish_tool_reply(state, reply)}

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
          {:error, _reason} -> {:reply, {:error, :session_failed}, state}
        end

      {:error, _reason} ->
        {:ok, decoder} = Decoder.new(state.config)
        {:reply, {:error, :session_failed}, %{state | decoder: decoder}}
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
  defp apply_decoder_event(:started, state), do: {:ok, self_yield(state)}
  defp apply_decoder_event({:partial, _text}, state), do: {:ok, state}

  defp apply_decoder_event({:final, text}, state) do
    case publish_audio_turn(state, text) do
      {:ok, state} -> {:ok, state}
      {:error, _reason} = error -> error
    end
  end

  defp publish_audio_turn(state, text) do
    end_ms = state.input_ms
    start_ms = max(end_ms - tone_ms(state.config, text), 0)
    fragment = %{text: text, start_ms: start_ms, end_ms: end_ms}

    {inference, events} = TurnInference.input_fragment(state.inference, fragment)

    with :ok <- emit_events(events, state),
         {:ok, turn_ref} <- first_turn_ref(events),
         {:ok, state} <- maybe_emit_tool(state, turn_ref, text) do
      {inference, close_events} = TurnInference.audio_pushed(inference, @default_input_gap_ms)
      state = %{state | inference: inference}

      with :ok <- emit_events(close_events, state) do
        {:ok, follow_up(state, turn_ref, text)}
      end
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
      {:ok, follow_up(state, turn_ref, text)}
    end
  end

  defp publish_tool_reply(state, reply) do
    turn_ref = make_ref()

    case Event.emit(state.channel, :turn_ended,
           turn_ref: turn_ref,
           text: "",
           endpointing: :inferred_gap
         ) do
      :ok -> start_reply(state, turn_ref, reply)
      _failure -> state
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

  defp first_turn_ref(events) do
    case Enum.find(events, fn {kind, _fields} ->
           kind in [:speech_started, :input_transcript, :turn_ended]
         end) do
      {_kind, fields} -> {:ok, Keyword.fetch!(fields, :turn_ref)}
      nil -> {:error, :session_failed}
    end
  end

  defp follow_up(state, turn_ref, text) do
    case tool_trigger(text) do
      {:tool, _name, _arguments} ->
        state

      :not_a_tool ->
        reply = @reply_prefix <> String.slice(text, 0, truncate_limit(state.config))
        start_reply(state, turn_ref, reply)
    end
  end

  defp maybe_emit_tool(state, turn_ref, text) do
    case tool_trigger(text) do
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

  defp tool_trigger(text) do
    case parse_tool_trigger(text) do
      {:tool, _name, _arguments} = tool -> tool
      :not_a_tool -> :not_a_tool
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

  defp open_burst(%{output: nil} = state, _seg_ref), do: {:ok, state}

  defp open_burst(%{output: %{output_ref: nil}} = state, _seg_ref), do: {:ok, state}

  defp open_burst(%{output: %{admitted?: true}} = state, _seg_ref), do: {:ok, state}

  defp open_burst(%{output: %{seg_ref: seg_ref}} = state, seg_ref) do
    {segmenter, events} = OutputSegmenter.admitted(state.segmenter, seg_ref)
    state = %{state | segmenter: segmenter, output: %{state.output | admitted?: true}}

    case apply_segmenter_events(events, state) do
      {:ok, state} -> {:ok, state}
      {:error, :buffer_overflow, state} -> {:error, :buffer_overflow, state}
    end
  end

  defp open_burst(state, _seg_ref), do: {:ok, state}

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
      output.interrupted? and output.awaiting != nil ->
        state

      output.interrupted? and output.output_ref == nil ->
        start_queued(%{state | output: nil})

      output.interrupted? ->
        complete_output(state)

      output.cursor >= byte_size(output.stream) and output.close_pending? and output.queue == [] and
        output.awaiting == nil and output.admitted? ->
        complete_output(state)

      true ->
        state
    end
  end

  defp handle_admit(state, turn_ref, output_ref) do
    case state.output do
      %{turn_ref: ^turn_ref} = output ->
        state = %{state | output: %{output | output_ref: output_ref}}

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

      _other ->
        case state.queued_reply do
          {^turn_ref, text, _output_ref} ->
            {:noreply, %{state | queued_reply: {turn_ref, text, output_ref}}}

          _other ->
            {:noreply, state}
        end
    end
  end

  defp start_reply(%{output: output} = state, turn_ref, text) when not is_nil(output) do
    %{state | queued_reply: {turn_ref, text, nil}}
  end

  defp start_reply(state, turn_ref, text) do
    with {:ok, reply} <- Encoder.encode(state.config, text) do
      stream =
        silence(state, @leading_silence_frames) <>
          reply <> silence(state, @trailing_silence_frames)

      output = %{
        turn_ref: turn_ref,
        text: text,
        output_ref: nil,
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
    else
      _error -> state
    end
  end

  defp start_queued(%{queued_reply: nil} = state), do: state

  defp start_queued(%{queued_reply: {turn_ref, text, output_ref}} = state) do
    state = start_reply(%{state | queued_reply: nil}, turn_ref, text)

    if output_ref do
      {:noreply, state} = handle_admit(state, turn_ref, output_ref)
      state
    else
      state
    end
  end

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

  defp self_yield(%{output: nil} = state), do: state

  defp self_yield(%{output: output} = state) do
    {segmenter, _events} = OutputSegmenter.finish(state.segmenter)

    state = %{
      state
      | segmenter: segmenter,
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

  defp parse_tool_trigger(text) when is_binary(text) do
    case String.split(String.trim(text), ~r/\s+/, parts: 3) do
      [keyword, name, encoded] when byte_size(name) in 1..256 ->
        if String.upcase(keyword) == "TOOL" and String.valid?(name) do
          decode_tool(name, encoded)
        else
          :not_a_tool
        end

      _other ->
        :not_a_tool
    end
  rescue
    _exception -> :not_a_tool
  end

  defp parse_tool_trigger(_text), do: :not_a_tool

  defp decode_tool(name, encoded) do
    case JSON.decode(encoded) do
      {:ok, arguments} ->
        if Vxpipe.CallEngine.Speech.ToolArguments.valid?(arguments),
          do: {:tool, name, arguments},
          else: :not_a_tool

      {:error, _reason} ->
        :not_a_tool
    end
  end

  defp summarize(result) when is_binary(result), do: String.slice(result, 0, 256)
  defp summarize(result), do: inspect(result)

  defp truncate_limit(config), do: max(config.maximum_text_bytes - byte_size(@reply_prefix), 0)

  defp duration_ms(config, bytes), do: div(bytes * 1_000, config.sample_rate * 2)

  defp tone_ms(config, text),
    do: max(byte_size(text) * config.unit_duration_ms, config.unit_duration_ms)
end
