defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.Session do
  @moduledoc """
  Credential-free local provider that behaves like GPT-Live.

  It shares the provider-neutral `Speech.Duplex.TurnInference` and
  `Speech.Duplex.OutputSegmenter` modules with the real OpenAI adapter so the
  default suite exercises the same room paths without a billable service. It
  reuses the Morse tone codec:

  - Caller tone is decoded into text and grouped into inferred turns.
  - A reply is Morse audio segmented by the output energy gate.
  - It yields its own reply when it decodes caller tone during output.
  - Caller text `TOOL <name> <json>` raises a delegated tool call whose result
    reopens a reply.
  """

  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder, Encoder}
  alias Vxpipe.CallEngine.Speech.Duplex.{OutputSegmenter, TurnInference}
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event}

  @reply_prefix "RECEIVED "
  @default_input_gap_ms 800
  @default_output_gap_ms 1_000
  @output_buffer_ms 60_000
  @pre_roll_ms 300

  @impl true
  def configure(options) do
    allowed = (Map.keys(Config.__struct__()) -- [:__struct__]) ++ [:output_transcript]

    with true <- is_list(options) and Keyword.keyword?(options),
         true <- length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))),
         true <- Enum.all?(Keyword.keys(options), &(&1 in allowed)),
         {output_transcript, rest} = Keyword.pop(options, :output_transcript, true),
         true <- is_boolean(output_transcript),
         {:ok, config} <- Config.new(rest) do
      Descriptor.new(
        kind: :sts,
        settings: Map.from_struct(config),
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

  @impl true
  def init(options) do
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = Keyword.fetch!(options, :channel)

    with {:ok, config} <- Config.new(Map.to_list(descriptor.settings)),
         {:ok, decoder} <- Decoder.new(config),
         {:ok, inference} <- TurnInference.new(gap_ms: @default_input_gap_ms),
         :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: descriptor.readiness) do
      {:ok,
       %{
         channel: channel,
         descriptor: descriptor,
         config: config,
         decoder: decoder,
         inference: inference,
         frame_bytes: div(config.sample_rate * 20, 1_000) * 2,
         input_ms: 0,
         output: nil,
         queued_reply: nil,
         pending_tools: %{}
       }}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

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

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def handle_info({:vxpipe_speech_output, _channel, turn_ref, output_ref}, state)
      when is_reference(turn_ref) and is_reference(output_ref) do
    handle_admit(state, turn_ref, output_ref)
  end

  def handle_info({:vxpipe_speech_credit, _channel, output_ref, credit, :ok}, state) do
    case state.output do
      %{output_ref: ^output_ref, awaiting: ^credit} = output ->
        pump(%{state | output: %{output | awaiting: nil}})

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
      :ok -> begin_reply(state, turn_ref, reply)
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
        begin_reply(state, turn_ref, reply)
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

  defp handle_admit(state, turn_ref, output_ref) do
    case state.output do
      %{turn_ref: ^turn_ref} = output ->
        {segmenter, events} = OutputSegmenter.admitted(output.segmenter, output.seg_ref)

        state = %{
          state
          | output: %{output | segmenter: segmenter, output_ref: output_ref, admitted?: true}
        }

        {:noreply, state} = apply_segmenter_events(events, state)
        pump(state)

      _other ->
        case state.queued_reply do
          {^turn_ref, text, _output_ref} ->
            {:noreply, %{state | queued_reply: {turn_ref, text, output_ref}}}

          _other ->
            {:noreply, state}
        end
    end
  end

  defp begin_reply(%{output: output} = state, turn_ref, text) when not is_nil(output) do
    %{state | queued_reply: {turn_ref, text, nil}}
  end

  defp begin_reply(state, turn_ref, text) do
    with {:ok, pcm} <- Encoder.encode(state.config, text),
         {:ok, segmenter} <- OutputSegmenter.new(segmenter_options(state.config)) do
      state = %{
        state
        | output: %{
            turn_ref: turn_ref,
            text: text,
            pcm: pcm,
            cursor: 0,
            segmenter: segmenter,
            seg_ref: nil,
            output_ref: nil,
            admitted?: false,
            awaiting: nil,
            interrupted?: false,
            complete_pending?: false,
            finished?: false
          }
      }

      pump(state) |> unwrap()
    else
      _error -> state
    end
  end

  defp unwrap({:noreply, state}), do: state

  defp segmenter_options(config) do
    [
      sample_rate: config.sample_rate,
      gap_ms: @default_output_gap_ms,
      pre_roll_ms: @pre_roll_ms,
      buffer_ms: @output_buffer_ms
    ]
  end

  defp pump(%{output: nil} = state), do: {:noreply, start_queued(state)}

  defp pump(%{output: %{interrupted?: true} = output} = state) do
    cond do
      output.awaiting != nil -> {:noreply, state}
      output.output_ref == nil -> {:noreply, start_queued(%{state | output: nil})}
      true -> complete_output(state)
    end
  end

  defp pump(%{output: output} = state) do
    cond do
      output.seg_ref == nil and output.finished? ->
        {:noreply, start_queued(%{state | output: nil})}

      output.seg_ref == nil ->
        feed_until_open(state)

      not output.admitted? ->
        {:noreply, state}

      output.awaiting != nil ->
        {:noreply, state}

      output.cursor < byte_size(output.pcm) ->
        feed_next(state)

      not output.complete_pending? ->
        close_segmenter(state)

      true ->
        complete_output(state)
    end
  end

  defp feed_until_open(state) do
    output = state.output

    if output.cursor >= byte_size(output.pcm) do
      {segmenter, events} = OutputSegmenter.finish(output.segmenter)

      state = %{
        state
        | output: %{output | segmenter: segmenter, cursor: byte_size(output.pcm), finished?: true}
      }

      {:noreply, state} = apply_segmenter_events(events, state)
      pump(state)
    else
      {frame, cursor} = next_frame(output, state.frame_bytes)
      {segmenter, events} = OutputSegmenter.push_pcm(output.segmenter, frame)
      state = %{state | output: %{output | segmenter: segmenter, cursor: cursor}}

      {:noreply, state} = apply_segmenter_events(events, state)

      if state.output.seg_ref == nil do
        feed_until_open(state)
      else
        {:noreply, state}
      end
    end
  end

  defp close_segmenter(state) do
    output = state.output
    {segmenter, events} = OutputSegmenter.finish(output.segmenter)
    state = %{state | output: %{output | segmenter: segmenter, complete_pending?: true}}

    {:noreply, state} = apply_segmenter_events(events, state)
    pump(state)
  end

  defp feed_next(state) do
    output = state.output
    {frame, cursor} = next_frame(output, state.frame_bytes)
    {segmenter, events} = OutputSegmenter.push_pcm(output.segmenter, frame)
    state = %{state | output: %{output | segmenter: segmenter, cursor: cursor}}

    {:noreply, state} = apply_segmenter_events(events, state)
    pump(state)
  end

  defp next_frame(output, frame_bytes) do
    remaining = byte_size(output.pcm) - output.cursor
    size = min(frame_bytes, remaining)
    {binary_part(output.pcm, output.cursor, size), output.cursor + size}
  end

  defp apply_segmenter_events(events, state) do
    Enum.reduce_while(events, {:noreply, state}, fn
      {:open, seg_ref}, {:noreply, state} ->
        {:cont, {:noreply, %{state | output: %{state.output | seg_ref: seg_ref}}}}

      {:audio, _seg_ref, pcm},
      {:noreply, %{output: %{admitted?: true, awaiting: nil} = output} = state} ->
        case Channel.submit(state.channel, output.output_ref, pcm) do
          {:ok, credit} ->
            {:halt, {:noreply, %{state | output: %{output | awaiting: credit}}}}

          _failure ->
            {:halt, {:noreply, %{state | output: %{output | interrupted?: true}}}}
        end

      _event, {:noreply, state} ->
        {:cont, {:noreply, state}}
    end)
  end

  defp complete_output(state) do
    output = state.output

    result =
      (
        emitted =
          Event.emit(state.channel, :output_transcript,
            turn_ref: output.turn_ref,
            text: output.text,
            final: true
          )

        with :ok <- emitted,
             :ok <-
               Event.emit(state.channel, :output_completed,
                 turn_ref: output.turn_ref,
                 request_ref: output.output_ref
               ) do
          :ok
        end
      )

    _ = result
    {:noreply, start_queued(%{state | output: nil})}
  end

  defp start_queued(%{queued_reply: nil} = state), do: state

  defp start_queued(%{queued_reply: {turn_ref, text, output_ref}} = state) do
    state = begin_reply(%{state | queued_reply: nil}, turn_ref, text)

    if output_ref do
      {:noreply, state} = handle_admit(state, turn_ref, output_ref)
      state
    else
      state
    end
  end

  defp self_yield(%{output: nil} = state), do: state

  defp self_yield(%{output: output} = state) do
    {segmenter, _events} = OutputSegmenter.finish(output.segmenter)
    state = %{state | output: %{output | interrupted?: true, segmenter: segmenter}}
    {:noreply, state} = pump(state)
    state
  end

  # Helpers ----------------------------------------------------------------

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
