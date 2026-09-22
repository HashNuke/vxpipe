defmodule Vxpipe.CallEngine.Provider.MorseCodeSTS.Session do
  @moduledoc "Local credential-free speech-to-speech proof provider with Morse conversation."
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder, Encoder}
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event}

  @turn_controls ["provider", "external", "hybrid"]
  @reply_prefix "RECEIVED "

  @impl true
  def configure(options) do
    allowed =
      (Map.keys(Config.__struct__()) -- [:__struct__]) ++ [:turn_control, :output_transcript]

    with true <- is_list(options) and Keyword.keyword?(options),
         true <- length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))),
         true <- Enum.all?(Keyword.keys(options), &(&1 in allowed)),
         {turn_control, rest} = Keyword.pop(options, :turn_control, "provider"),
         true <- turn_control in @turn_controls,
         {output_transcript, rest} = Keyword.pop(rest, :output_transcript, true),
         true <- is_boolean(output_transcript),
         {:ok, config} <- Config.new(rest) do
      Descriptor.new(
        kind: :sts,
        settings: Map.put(Map.from_struct(config), :turn_control, turn_control),
        input_format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: config.sample_rate,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: config.sample_rate,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :morse_code,
          model: :morse_code,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: if(turn_control == "external", do: :external, else: :provider_gap),
        speech_start?: turn_control != "external",
        turn_control: turn_control,
        turn_control_supported: @turn_controls,
        input_transcript?: true,
        output_transcript?: output_transcript,
        output_settlement: :transcript_end,
        history_reconciliation?: false
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
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
  def input_activity(pid, boundary) when boundary in [:started, :ended],
    do: GenServer.call(pid, {:input_activity, boundary}, 5_000)

  @impl true
  def interrupt(pid, turn_ref) when is_reference(turn_ref),
    do: GenServer.call(pid, {:interrupt, turn_ref}, 5_000)

  @impl true
  def send_tool_result(pid, call_ref, result) when is_reference(call_ref),
    do: GenServer.call(pid, {:send_tool_result, call_ref, result}, 5_000)

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

    with {:ok, config} <- config_from_descriptor(descriptor),
         {:ok, decoder} <- Decoder.new(config),
         :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: descriptor.readiness) do
      {:ok,
       %{
         channel: channel,
         descriptor: descriptor,
         config: config,
         decoder: decoder,
         input_turn: nil,
         external_started?: false,
         decoder_final: nil,
         pending_replies: %{},
         pending_tools: %{},
         output: nil
       }}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:push_audio, audio}, _from, state) when is_binary(audio) do
    case Decoder.push(state.decoder, audio) do
      {:ok, decoder, events} ->
        publish_decoder_events(events, %{state | decoder: decoder})

      {:error, _reason} ->
        {:ok, decoder} = Decoder.new(state.config)
        {:reply, {:error, :session_failed}, %{state | decoder: decoder}}
    end
  end

  def handle_call({:push_text, reference, text}, _from, state)
      when is_reference(reference) and is_binary(text) do
    case classify_text_input(text, state.config) do
      {:tool, name, arguments} ->
        turn = make_ref()
        call_ref = make_ref()

        with :ok <-
               Event.emit(state.channel, :input_submitted,
                 request_ref: reference,
                 provenance: :locally_measured
               ),
             :ok <- emit_input_transcript(state, turn, text, true),
             :ok <-
               Event.emit(state.channel, :tool_call,
                 call_ref: call_ref,
                 turn_ref: turn,
                 tool_name: name,
                 arguments: arguments
               ),
             {:ok, state} <- close_input_turn(state, turn, text) do
          state = %{
            state
            | pending_tools: Map.put(state.pending_tools, call_ref, %{turn_ref: turn, name: name})
          }

          {:reply, :ok, state}
        else
          _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
        end

      {:reply, reply} ->
        turn = make_ref()

        with :ok <-
               Event.emit(state.channel, :input_submitted,
                 request_ref: reference,
                 provenance: :locally_measured
               ),
             :ok <- emit_input_transcript(state, turn, text, true),
             {:ok, state} <- close_input_turn(state, turn, text) do
          {:reply, :ok, put_pending_reply(state, turn, reply)}
        else
          _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:input_activity, boundary},
        _from,
        %{descriptor: %{turn_control: "provider"}} = state
      )
      when boundary in [:started, :ended] do
    {:reply, {:error, :unsupported_operation}, state}
  end

  def handle_call({:input_activity, :started}, _from, state) do
    {:reply, :ok, %{state | external_started?: true, input_turn: state.input_turn || make_ref()}}
  end

  def handle_call({:input_activity, :ended}, _from, state) do
    case Decoder.flush(state.decoder) do
      {:ok, decoder, events} ->
        state = %{state | decoder: decoder, external_started?: false}

        with {:ok, state} <- apply_decoder_events(events, state, external_end?: true),
             {:ok, state} <- finish_stored_external_turn(state) do
          {:reply, :ok, state}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, _reason} ->
        {:ok, decoder} = Decoder.new(state.config)
        {:reply, {:error, :session_failed}, %{state | decoder: decoder}}
    end
  end

  def handle_call({:interrupt, turn_ref}, _from, state) when is_reference(turn_ref) do
    {state, cancellations} = take_tool_cancellations(state, turn_ref)
    state = %{state | pending_replies: Map.delete(state.pending_replies, turn_ref)}
    state = fence_local_output(state, turn_ref)

    with :ok <- Event.emit(state.channel, :interrupted, turn_ref: turn_ref),
         :ok <- emit_tool_cancellations(state, cancellations) do
      {:reply, :ok, state}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:send_tool_result, call_ref, _result}, _from, state)
      when is_reference(call_ref) do
    case Map.fetch(state.pending_tools, call_ref) do
      {:ok, _tool} ->
        {:reply, :ok, %{state | pending_tools: Map.delete(state.pending_tools, call_ref)}}

      :error ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def handle_info({:vxpipe_speech_output, _channel, turn_ref, output_ref}, state)
      when is_reference(turn_ref) and is_reference(output_ref) do
    case Map.fetch(state.pending_replies, turn_ref) do
      {:ok, reply} ->
        start_output(state, turn_ref, output_ref, reply)

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:vxpipe_speech_credit, _channel, output_ref, credit, :ok},
        %{output: %{output_ref: output_ref, awaiting: credit} = output} = state
      ) do
    state = %{state | output: %{output | awaiting: nil}}

    if output.interrupted? and not output.completed_emitted? do
      _ =
        Event.emit(state.channel, :output_completed,
          turn_ref: output.turn_ref,
          request_ref: output.output_ref
        )

      {:noreply, %{state | output: nil}}
    else
      continue_output(state)
    end
  end

  def handle_info({:vxpipe_speech_credit, _channel, _output_ref, _credit, :ok}, state) do
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :morse_code_sts_session)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp config_from_descriptor(%{settings: settings}) when is_map(settings) do
    settings
    |> Map.delete(:turn_control)
    |> Map.to_list()
    |> Config.new()
  end

  defp publish_decoder_events([], state), do: {:reply, :ok, state}

  defp publish_decoder_events(events, state) do
    case apply_decoder_events(events, state, external_end?: false) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, _reason} -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  defp apply_decoder_events(events, state, options) do
    Enum.reduce_while(events, {:ok, state}, fn event, {:ok, state} ->
      case apply_decoder_event(event, state, options) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp apply_decoder_event(:started, %{descriptor: %{speech_start?: false}} = state, _options) do
    {:ok, %{state | input_turn: state.input_turn || make_ref()}}
  end

  defp apply_decoder_event(:started, state, _options) do
    turn = state.input_turn || make_ref()
    state = %{state | input_turn: turn}

    case Event.emit(state.channel, :speech_started, turn_ref: turn) do
      :ok -> {:ok, state}
      _failure -> {:error, :session_failed}
    end
  end

  defp apply_decoder_event({:partial, text}, state, _options) do
    turn = state.input_turn || make_ref()
    state = %{state | input_turn: turn}

    case emit_input_transcript(state, turn, text, false) do
      :ok -> {:ok, state}
      _failure -> {:error, :session_failed}
    end
  end

  defp apply_decoder_event({:final, text}, %{descriptor: %{turn_control: mode}} = state, options)
       when mode in ["external", "hybrid"] do
    turn = state.input_turn || make_ref()
    state = %{state | input_turn: turn, decoder_final: text}

    with :ok <- emit_input_transcript(state, turn, text, true) do
      if Keyword.get(options, :external_end?, false),
        do: finish_input_turn(state, turn, text),
        else: {:ok, state}
    else
      _failure -> {:error, :session_failed}
    end
  end

  defp apply_decoder_event({:final, text}, state, _options) do
    turn = state.input_turn || make_ref()
    state = %{state | input_turn: turn}

    with :ok <- emit_input_transcript(state, turn, text, true) do
      finish_input_turn(state, turn, text)
    else
      _failure -> {:error, :session_failed}
    end
  end

  defp finish_stored_external_turn(%{input_turn: nil} = state), do: {:ok, state}
  defp finish_stored_external_turn(%{decoder_final: nil} = state), do: {:ok, state}

  defp finish_stored_external_turn(%{input_turn: turn, decoder_final: text} = state) do
    finish_input_turn(state, turn, text)
  end

  defp finish_input_turn(state, turn, text) do
    case classify_audio_input(text, state.config) do
      {:tool, name, arguments} ->
        call_ref = make_ref()

        with :ok <-
               Event.emit(state.channel, :tool_call,
                 call_ref: call_ref,
                 turn_ref: turn,
                 tool_name: name,
                 arguments: arguments
               ),
             {:ok, state} <- close_input_turn(state, turn, text) do
          {:ok,
           %{
             state
             | pending_tools:
                 Map.put(state.pending_tools, call_ref, %{turn_ref: turn, name: name})
           }}
        else
          _failure -> {:error, :session_failed}
        end

      {:reply, reply} ->
        with {:ok, state} <- close_input_turn(state, turn, text) do
          {:ok, put_pending_reply(state, turn, reply)}
        end

      {:error, _reason} ->
        {:error, :session_failed}
    end
  end

  defp emit_input_transcript(%{descriptor: %{input_transcript?: false}}, _turn, _text, _final),
    do: :ok

  defp emit_input_transcript(state, turn, text, final) do
    Event.emit(state.channel, :input_transcript, turn_ref: turn, text: text, final: final)
  end

  defp close_input_turn(state, turn, text) do
    endpointing = state.descriptor.endpointing

    case Event.emit(state.channel, :turn_ended,
           turn_ref: turn,
           text: text,
           endpointing: endpointing
         ) do
      :ok -> {:ok, %{state | input_turn: nil, decoder_final: nil}}
      _failure -> {:error, :session_failed}
    end
  end

  defp put_pending_reply(state, turn, reply) do
    %{state | pending_replies: Map.put(state.pending_replies, turn, reply)}
  end

  defp reply_text(text, config) do
    max_input = max(config.maximum_text_bytes - byte_size(@reply_prefix), 0)
    kept = String.slice(text, 0, max_input)
    @reply_prefix <> kept
  end

  defp reply_for_text(text, config) do
    with true <- String.valid?(text) and byte_size(text) in 1..4096,
         reply = reply_text(text, config),
         {:ok, _encoder} <- Encoder.start(config, reply) do
      {:ok, reply}
    else
      false -> {:error, :invalid_text}
      {:error, reason} -> {:error, reason}
    end
  end

  defp classify_text_input(text, config) do
    with true <- String.valid?(text) and byte_size(text) in 1..4096,
         {:tool, _name, _arguments} = tool <- parse_tool_trigger(text) do
      tool
    else
      false ->
        {:error, :invalid_text}

      :not_a_tool ->
        case reply_for_text(text, config) do
          {:ok, reply} -> {:reply, reply}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp classify_audio_input(text, config) do
    case parse_tool_trigger(text) do
      {:tool, _name, _arguments} = tool -> tool
      :not_a_tool -> {:reply, reply_text(text, config)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_tool_trigger(text) when is_binary(text) do
    case String.split(String.trim(text), ~r/\s+/, parts: 3) do
      [keyword, name, encoded] when byte_size(name) in 1..256 ->
        if String.upcase(keyword) == "TOOL" and String.valid?(name) do
          with {:ok, arguments} <- decode_tool_arguments(encoded),
               true <- Vxpipe.CallEngine.Speech.ToolArguments.valid?(arguments) do
            {:tool, name, arguments}
          else
            _invalid -> {:error, :invalid_tool_arguments}
          end
        else
          :not_a_tool
        end

      _other ->
        :not_a_tool
    end
  end

  defp decode_tool_arguments(encoded) when is_binary(encoded) do
    case JSON.decode(encoded) do
      {:ok, arguments} -> {:ok, arguments}
      {:error, _reason} -> {:error, :invalid_tool_arguments}
    end
  rescue
    _exception -> {:error, :invalid_tool_arguments}
  end

  defp take_tool_cancellations(state, turn_ref) do
    {cancelled, pending} =
      Enum.split_with(state.pending_tools, fn {_call, tool} -> tool.turn_ref == turn_ref end)

    {%{state | pending_tools: Map.new(pending)}, Enum.map(cancelled, &elem(&1, 0))}
  end

  defp fence_local_output(%{output: %{turn_ref: turn} = output} = state, turn) do
    output = %{output | encoder: nil, interrupted?: true}
    state = %{state | output: output}

    if not output.completed_emitted? and is_nil(output.awaiting) do
      _ =
        Event.emit(state.channel, :output_completed,
          turn_ref: turn,
          request_ref: output.output_ref
        )

      %{state | output: nil}
    else
      state
    end
  end

  defp fence_local_output(state, _turn_ref), do: state

  defp emit_tool_cancellations(state, []) do
    _ = state
    :ok
  end

  defp emit_tool_cancellations(state, [call_ref | rest]) do
    case Event.emit(state.channel, :tool_cancelled, call_ref: call_ref) do
      :ok -> emit_tool_cancellations(state, rest)
      _failure -> {:error, :session_failed}
    end
  end

  defp start_output(state, turn_ref, output_ref, reply) do
    with {:ok, encoder} <- Encoder.start(state.config, reply),
         :ok <- maybe_emit_output_transcript(state, turn_ref, reply) do
      state = %{
        state
        | pending_replies: Map.delete(state.pending_replies, turn_ref),
          output: %{
            turn_ref: turn_ref,
            output_ref: output_ref,
            encoder: encoder,
            awaiting: nil,
            interrupted?: false,
            completed_emitted?: false
          }
      }

      submit_next_chunk(state)
    else
      _failure -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  defp maybe_emit_output_transcript(%{descriptor: %{output_transcript?: false}}, _turn, _reply),
    do: :ok

  defp maybe_emit_output_transcript(state, turn_ref, reply) do
    Event.emit(state.channel, :output_transcript, turn_ref: turn_ref, text: reply, final: true)
  end

  defp submit_next_chunk(%{output: %{encoder: nil}} = state), do: {:noreply, state}

  defp submit_next_chunk(%{output: %{interrupted?: true}} = state), do: {:noreply, state}

  defp submit_next_chunk(%{output: %{encoder: encoder} = output} = state) do
    case Encoder.next(encoder, chunk_samples(state.config)) do
      {:ok, pcm, encoder} ->
        case Channel.submit(state.channel, output.output_ref, pcm) do
          {:ok, credit} ->
            {:noreply, %{state | output: %{output | encoder: encoder, awaiting: credit}}}

          _failure ->
            {:stop, {:shutdown, :session_failed}, state}
        end

      :done ->
        case Event.emit(state.channel, :output_completed,
               turn_ref: output.turn_ref,
               request_ref: output.output_ref
             ) do
          :ok ->
            {:noreply,
             %{state | output: %{output | encoder: nil, awaiting: nil, completed_emitted?: true}}}

          _failure ->
            {:stop, {:shutdown, :session_failed}, state}
        end
    end
  end

  defp continue_output(%{output: %{encoder: nil}} = state), do: {:noreply, state}

  defp continue_output(%{output: %{interrupted?: true}} = state), do: {:noreply, state}

  defp continue_output(state), do: submit_next_chunk(state)

  defp chunk_samples(config), do: div(config.sample_rate * 20, 1_000)
end
