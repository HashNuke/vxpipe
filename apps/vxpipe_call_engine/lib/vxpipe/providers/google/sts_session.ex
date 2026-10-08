defmodule Vxpipe.Providers.Google.STSSession do
  @moduledoc """
  Gemini 3.8 Live speech-to-speech adapter behind the credentialed boundary.

  Ordinary tests use fixture payloads and fake sockets; no network account is
  needed. Configured agents select `gemini-3.8-live` through the Google manifest
  and resolve the saved Google credential privately. Real-provider acceptance
  belongs to the tagged hosted and phone lanes; fixtures alone do not establish
  hosted continuity or interrupted-history reconciliation.
  """

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, SessionTree, STSProvider}

  alias Vxpipe.Providers.Google.{
    STS,
    STSInput,
    STSOpening,
    STSResponseDelivery,
    STSResponses,
    STSResumption,
    STSSubmission,
    STSSocket,
    STSToolCall
  }

  @setup_timeout 15_000
  import Vxpipe.Providers.Google.STSOutput,
    only: [
      buffer_audio: 2,
      buffer_transcript: 2,
      publish_transcript: 1,
      open_output: 3,
      mark_generation_done: 1,
      drain_output: 1
    ]

  @derive {Inspect, only: [:ready?]}
  defstruct [
    :channel,
    :socket_supervisor,
    :config,
    :wire,
    :wire_monitor,
    :wire_module,
    :wire_options,
    :setup_timer,
    :pending_wire,
    :retiring_wire,
    :pending_monitor,
    :pending_handle,
    :resume_attempt,
    :resume_timer,
    :resumption_timeout_ms,
    :resume_deadline,
    ready?: false,
    renew_requested?: false,
    resuming?: false,
    retirement_ack?: false,
    retry_pending?: false,
    resumption_handle: nil,
    fixed_opening: nil,
    caller: nil,
    input_turn: nil,
    input_text: nil,
    input_ended?: false,
    audio_fenced?: false,
    generation_pending_done?: false,
    model_turn_complete?: true,
    awaiting_model_activity?: false,
    awaiting_audio_final?: false,
    audio_after_caller_end?: false,
    interaction_status: :idle,
    resumption_ambiguous?: false,
    clean_input_boundary?: false,
    clean_exchange?: false,
    clean_model_content?: false,
    pending_input: nil,
    rotation_reason: nil,
    response_start?: false,
    interaction_context: nil,
    responses: nil,
    output: nil,
    output_text: nil,
    audio_buffer: [],
    pending_tools: %{},
    usage: nil
  ]

  @impl true
  def configure(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- length(options) == length(Enum.uniq(Keyword.keys(options))),
         {response_start?, public_options} <- Keyword.pop(options, :response_start?, false),
         true <- is_boolean(response_start?),
         {:ok, public} <- STS.public_options(public_options) do
      Descriptor.new(
        kind: :sts,
        response_start?: response_start?,
        settings: public,
        input_format: STS.pcm_format(public.input_sample_rate),
        format: STS.pcm_format(public.output_sample_rate),
        usage_identity: %{provider: :google, model: public.model, provenance: :provider_reported},
        readiness: :provider_acknowledged,
        endpointing:
          if(public.turn_control == "external", do: :external, else: :provider_semantic),
        speech_start?: public.turn_control != "external",
        turn_control: public.turn_control,
        turn_control_supported: ["provider", "external"],
        input_transcript?: true,
        output_transcript?: true,
        output_settlement: :generation_boundary,
        history_reconciliation?: false,
        output_shape: :turns,
        barge_in: :room,
        continuity: :resumption_handle,
        tool_cancellation?: true,
        hold: :stop
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def configure(_options), do: {:error, :invalid_configuration}

  @impl true
  def start_link(options), do: STSProvider.start_link(__MODULE__, options)

  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:push_audio, audio}, 5_000)

  @impl true
  def push_text(pid, reference, text) when is_reference(reference) and is_binary(text),
    do: GenServer.call(pid, {:push_text, reference, text}, 5_000)

  @impl true
  def begin_opening(pid, reference, opening) when is_reference(reference),
    do: GenServer.call(pid, {:begin_opening, reference, opening}, 5_000)

  @impl true
  def input_activity(pid, boundary) when boundary in [:started, :ended],
    do: GenServer.call(pid, {:input_activity, boundary}, 5_000)

  @impl true
  def input_quiescent?(pid), do: GenServer.call(pid, :input_quiescent?, 1_000)

  @impl true
  def submit_input(pid, context, operation) when is_reference(context),
    do: GenServer.call(pid, {:submit_input, context, operation}, 5_000)

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
    allocation = Keyword.fetch!(options, :allocation)
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    wire_module = Keyword.get(private, :wire_module, STSSocket)
    wire_options = Keyword.get(private, :wire_options, [])
    resume_timeout = Keyword.get(private, :resumption_timeout_ms, 5_000)

    with :ok <- STS.validate(config),
         {:ok, expected} <-
           configure(
             model: config.model,
             voice: config.voice,
             turn_control: config.turn_control,
             response_start?: descriptor.response_start?
           ),
         true <- descriptor == expected,
         true <- is_atom(wire_module) and is_list(wire_options) and Keyword.keyword?(wire_options),
         true <- STSResumption.valid_timeout?(resume_timeout),
         :ok <- Channel.bind(channel) do
      {:ok,
       %__MODULE__{
         channel: channel,
         socket_supervisor: SessionTree.providers(allocation),
         config: config,
         wire_module: wire_module,
         wire_options: wire_options,
         response_start?: descriptor.response_start?,
         responses: STSResponses.new(),
         resumption_timeout_ms: resume_timeout
       }, {:continue, :connect}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    with {:ok, wire} <- STSResumption.start_socket(state, []),
         :ok <- state.wire_module.send_control(wire, JSON.encode!(STS.setup(state.config))) do
      timer = Process.send_after(self(), :setup_timeout, @setup_timeout)
      {:noreply, %{state | wire: wire, wire_monitor: Process.monitor(wire), setup_timer: timer}}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  @impl true
  def handle_call(
        {:submit_input, context, operation},
        from,
        %{response_start?: true} = state
      ) do
    STSSubmission.submit({:context, context, operation}, from, state)
  end

  def handle_call({:submit_input, _context, _operation}, _from, state),
    do: {:reply, {:error, :unsupported_operation}, state}

  def handle_call(:input_quiescent?, _from, state),
    do: {:reply, STSResumption.input_quiescent?(state), state}

  def handle_call(command, from, state)
      when is_tuple(command) and
             elem(command, 0) in [:push_audio, :push_text, :begin_opening, :input_activity] do
    if state.response_start?,
      do: {:reply, {:error, :unsupported_operation}, state},
      else: STSSubmission.submit({:command, command}, from, state)
  end

  def handle_call({:interrupt, turn_ref}, _from, %{response_start?: true} = state)
      when is_reference(turn_ref) do
    case STSResponseDelivery.interrupt(state, turn_ref) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, reason} ->
        emit_failure(:interrupt, reason)
        {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:interrupt, turn_ref}, _from, state) when is_reference(turn_ref) do
    if current_legacy_turn?(state, turn_ref),
      do: fail_legacy_interrupt(state),
      else: {:reply, :ok, state}
  end

  def handle_call({:send_tool_result, call_ref, result}, _from, state)
      when is_reference(call_ref) do
    case Map.fetch(state.pending_tools, call_ref) do
      {:ok, %{id: id, name: name}} ->
        case send_tool_response(state, id, name, result) do
          :ok ->
            {:reply, :ok,
             %{state | pending_tools: Map.delete(state.pending_tools, call_ref)}
             |> STSResumption.model_work()
             |> STSResumption.await_model_activity()}

          {:error, _reason} ->
            {:reply, {:error, :invalid_tool_result}, state}
        end

      :error ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  def handle_call(:close, _from, state) do
    if state.wire, do: state.wire_module.close(state.wire)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:vxpipe_socket_retired, wire}, %{retiring_wire: wire} = state)
      when is_pid(wire) do
    {:noreply, %{state | retirement_ack?: true}}
  end

  def handle_info(
        {:vxpipe_sts_transport, wire, {:message, payload}},
        %{retiring_wire: wire} = state
      )
      when is_pid(wire) do
    with {:ok, events} <- STS.decode(payload),
         true <- Enum.all?(events, &retirement_control?/1),
         {:ok, state} <- apply_wire_events(events, state) do
      {:noreply, state}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  @impl true
  def handle_info({:vxpipe_sts_transport, wire, {:message, payload}}, %{wire: wire} = state) do
    case STS.decode(payload) do
      {:ok, events} ->
        case apply_wire_events(events, state) do
          {:ok, state} -> {:noreply, STSResumption.advance(state)}
          {:error, _reason} -> {:stop, {:shutdown, :session_failed}, state}
        end

      {:error, :provider_failure} ->
        emit_failure(:decode, :provider_failure)
        {:stop, {:shutdown, :session_failed}, state}

      {:error, reason} ->
        emit_failure(:decode, reason)
        {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {:vxpipe_sts_transport, wire, {:message, payload}},
        %{pending_wire: wire} = state
      ) do
    with {:ok, events} <- STS.decode(payload),
         true <- Enum.member?(events, :ready),
         {:ok, state} <- apply_wire_events(events -- [:ready], STSResumption.complete(state)),
         {:ok, state} <- STSSubmission.release(state) do
      {:noreply, state}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info({:vxpipe_socket_connected, wire}, %{pending_wire: wire} = state) do
    case STSResumption.connected(state) do
      :ok -> {:noreply, state}
      _failure -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {:vxpipe_sts_transport, wire, {:closed, :session_active}},
        %{pending_wire: wire} = state
      ),
      do: {:noreply, %{state | retry_pending?: true}}

  def handle_info(
        {:vxpipe_sts_transport, wire, {:closed, _reason}},
        %{pending_wire: wire} = state
      ),
      do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info({:vxpipe_sts_transport, wire, {:closed, _reason}}, %{wire: wire} = state),
    do: recover_connection(state)

  def handle_info(
        {:DOWN, monitor, :process, _owner, _reason},
        %{pending_input: %{monitor: monitor}} = state
      ),
      do: {:noreply, %{state | pending_input: nil}}

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{pending_monitor: monitor, pending_wire: wire, retry_pending?: true} = state
      ) do
    case STSResumption.retry_replacement(state) do
      {:ok, state} -> {:noreply, state}
      {:error, _reason} -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{pending_monitor: monitor, pending_wire: wire} = state
      ),
      do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{wire_monitor: monitor, retiring_wire: wire, retirement_ack?: true} = state
      ) do
    case STSResumption.retired(state) do
      {:ok, state} -> {:noreply, state}
      {:error, _reason} -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{wire_monitor: monitor, wire: wire} = state
      ),
      do: recover_connection(state)

  def handle_info(:setup_timeout, %{ready?: false} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info({:resumption_timeout, attempt}, %{resume_attempt: attempt} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(:resumption_unsafe, state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(
        {:vxpipe_speech_output, channel, turn_ref, output_ref},
        %{response_start?: true, channel: channel} = state
      ) do
    case STSResponseDelivery.grant(state, turn_ref, output_ref) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        emit_failure(:output_grant, reason)
        {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info({:vxpipe_speech_output, channel, turn_ref, output_ref}, state)
      when is_reference(turn_ref) and is_reference(output_ref) do
    cond do
      channel != state.channel ->
        {:noreply, state}

      turn_ref != state.input_turn ->
        {:stop, {:shutdown, :session_failed}, state}

      true ->
        with {:ok, state} <- publish_transcript(open_output(state, turn_ref, output_ref)),
             {:ok, state} <- drain_output(state) do
          {:noreply, state}
        else
          {:error, _reason} -> {:stop, {:shutdown, :session_failed}, state}
        end
    end
  end

  def handle_info(
        {:vxpipe_speech_credit, channel, output_ref, credit, :ok},
        %{response_start?: true, channel: channel} = state
      ) do
    case STSResponseDelivery.credit(state, output_ref, credit) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        emit_failure(:output_credit, reason)
        {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {:vxpipe_speech_credit, channel, output_ref, credit, :ok},
        %{output: %{output_ref: output_ref, awaiting: credit} = output} = state
      )
      when channel == state.channel do
    state = %{state | output: %{output | awaiting: nil}}

    if output.interrupted? and not output.completed_emitted? do
      _ =
        Event.emit(state.channel, :output_completed,
          turn_ref: output.turn_ref,
          request_ref: output.output_ref
        )

      {:noreply, %{state | output: nil}}
    else
      case drain_output(state) do
        {:ok, state} -> {:noreply, state}
        {:error, _reason} -> {:stop, {:shutdown, :session_failed}, state}
      end
    end
  end

  def handle_info({:vxpipe_speech_credit, _channel, _output_ref, _credit, :ok}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_speech_output_settled, channel, turn, ref, _played_ms},
        %{response_start?: true, channel: channel} = state
      ) do
    {:ok, state} = STSResponseDelivery.settle(state, turn, ref)
    {:noreply, STSResumption.advance(state)}
  end

  def handle_info(
        {:vxpipe_speech_output_settled, channel, turn, ref, _played_ms},
        %{channel: channel, output: %{turn_ref: turn, output_ref: ref}} = state
      ) do
    output_text = if state.input_turn == turn, do: nil, else: state.output_text
    state = %{state | output: nil, output_text: output_text}

    state =
      if state.input_turn == turn,
        do: %{state | input_turn: nil, input_text: nil, input_ended?: false},
        else: state

    {:noreply, STSResumption.advance(state)}
  end

  def handle_info(
        {:vxpipe_speech_response_discard, channel, turn},
        %{response_start?: true, channel: channel} = state
      ) do
    case STSResponseDelivery.discard(state, turn) do
      {:ok, state} ->
        {:noreply, STSResumption.advance(state)}

      {:error, reason} ->
        emit_failure(:output_discard, reason)
        {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp fail_legacy_interrupt(state) do
    emit_failure(:interrupt, :unsupported_interrupt)
    {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
  end

  defp recover_connection(state) do
    if STSResumption.recoverable?(state),
      do: {:noreply, STSResumption.request(state)},
      else: {:stop, {:shutdown, :session_failed}, state}
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :google_sts)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp apply_wire_events(events, state) do
    Enum.reduce_while(events, {:ok, state}, fn event, {:ok, state} ->
      state =
        case event do
          :ready -> state
          {:go_away, _remaining_ms} -> state
          {:resumption, _handle} -> state
          {:usage, _metadata} -> state
          :model_activity -> STSResumption.model_work(state)
          :model_content -> STSResumption.observed_model_content(state)
          {:output_transcript, _text} -> STSResumption.observed_model_content(state)
          {:tool_call, _id, _name, _args} -> STSResumption.observed_model_content(state)
          _conversation_event -> state
        end

      case apply_wire_event(event, state) do
        {:ok, state} ->
          {:cont, {:ok, state}}

        {:error, reason} = error ->
          if is_nil(state.fixed_opening), do: emit_failure(event_kind(event), reason)
          {:halt, error}
      end
    end)
  end

  defp apply_wire_event(event, %{fixed_opening: opening} = state)
       when not is_nil(opening) do
    case STSOpening.accept(opening, event) do
      {:buffered, opening} ->
        {:ok, %{state | fixed_opening: opening}}

      {:release, events} ->
        apply_wire_events(events, %{state | fixed_opening: nil})

      :pass ->
        apply_session_event(event, state)

      {:error, reason} ->
        emit_failure(:fixed_opening, reason)
        {:error, :session_failed}
    end
  end

  defp apply_wire_event(event, state), do: apply_session_event(event, state)

  defp event_kind(event) when is_tuple(event), do: elem(event, 0)
  defp event_kind(event) when is_atom(event), do: event

  defp emit_failure(stage, reason) when is_atom(stage) and is_atom(reason) do
    :telemetry.execute(
      [:vxpipe, :providers, :google, :sts, :failure],
      %{count: 1},
      %{stage: stage, reason: reason}
    )
  end

  defp apply_session_event(:ready, %{ready?: false} = state) do
    Process.cancel_timer(state.setup_timer)

    with :ok <- Event.emit(state.channel, :ready, readiness: :provider_acknowledged) do
      {:ok, %{state | ready?: true, setup_timer: nil}}
    end
  end

  defp apply_session_event(:ready, state), do: {:ok, state}

  defp apply_session_event(:model_activity, state), do: {:ok, state}
  defp apply_session_event(:model_content, state), do: {:ok, state}

  defp apply_session_event(:activity_start, %{config: %{turn_control: "external"}} = state),
    do: {:ok, state}

  defp apply_session_event(:activity_start, state), do: STSInput.start(state)

  defp apply_session_event(:activity_end, %{config: %{turn_control: "external"}} = state),
    do: {:ok, state}

  defp apply_session_event(:activity_end, state), do: STSInput.finish(state)

  defp apply_session_event({:input_transcript, text, final?}, state),
    do: STSInput.transcript(state, text, final?)

  defp apply_session_event({:audio, pcm}, %{response_start?: true} = state) do
    if byte_size(pcm) > 0 and rem(byte_size(pcm), 2) == 0,
      do: STSResponseDelivery.audio(state, pcm),
      else: {:error, :session_failed}
  end

  defp apply_session_event({:audio, pcm}, %{audio_fenced?: true} = state) do
    _ = pcm
    {:ok, state}
  end

  defp apply_session_event(
         {:audio, pcm},
         %{output: %{interrupted?: true, turn_ref: old}, input_turn: turn} = state
       )
       when is_reference(turn) and turn != old do
    if byte_size(pcm) > 0 and rem(byte_size(pcm), 2) == 0,
      do: buffer_audio(state, pcm),
      else: {:error, :session_failed}
  end

  defp apply_session_event({:audio, pcm}, %{output: %{interrupted?: true}} = state) do
    _ = pcm
    {:ok, state}
  end

  defp apply_session_event({:audio, pcm}, %{input_turn: nil} = state) do
    _ = pcm
    {:ok, state}
  end

  defp apply_session_event({:audio, pcm}, state) do
    if byte_size(pcm) > 0 and rem(byte_size(pcm), 2) == 0 do
      with {:ok, state} <- buffer_audio(state, pcm),
           {:ok, state} <- drain_output(state) do
        {:ok, state}
      end
    else
      {:error, :session_failed}
    end
  end

  defp apply_session_event({:output_transcript, text}, %{response_start?: true} = state),
    do: STSResponseDelivery.transcript(state, text)

  defp apply_session_event({:output_transcript, text}, %{input_turn: nil} = state) do
    _ = text
    {:ok, state}
  end

  defp apply_session_event({:output_transcript, text}, state), do: buffer_transcript(state, text)

  defp apply_session_event(:generation_complete, %{response_start?: true} = state),
    do: STSResponseDelivery.generation_end(state)

  defp apply_session_event(:generation_complete, state) do
    drain_output(mark_generation_done(state))
  end

  defp apply_session_event({:turn_complete, status}, %{response_start?: true} = state) do
    with {:ok, state} <- STSResponseDelivery.model_end(state),
         do: {:ok, %{state | model_turn_complete?: true, interaction_status: status}}
  end

  defp apply_session_event({:turn_complete, status}, state),
    do: {:ok, %{state | model_turn_complete?: true, interaction_status: status}}

  defp apply_session_event(:interrupted, %{response_start?: true} = state),
    do: STSResponseDelivery.interrupted(state)

  defp apply_session_event(:interrupted, %{input_turn: nil} = state), do: {:ok, state}

  defp apply_session_event(:interrupted, state) do
    turn = state.input_turn

    case Event.emit(state.channel, :interrupted, turn_ref: turn) do
      :ok -> full_fence(state)
      :discarded -> full_fence(state)
      _failure -> {:error, :session_failed}
    end
  end

  defp apply_session_event({:tool_call, id, name, args}, %{response_start?: true} = state) do
    with {:ok, state, turn} <- STSResponseDelivery.tool_turn(state),
         do: STSToolCall.start(state, turn, id, name, args)
  end

  defp apply_session_event({:tool_call, id, name, args}, state),
    do: STSToolCall.start(state, state.input_turn, id, name, args)

  defp apply_session_event({:tool_cancel, id}, state), do: STSToolCall.cancel(state, id)

  defp apply_session_event({:go_away, remaining_ms}, state),
    do: {:ok, STSResumption.request(state, remaining_ms)}

  defp apply_session_event({:resumption, handle}, state),
    do: {:ok, STSResumption.observe_handle(state, handle)}

  defp apply_session_event({:usage, metadata}, state) when is_map(metadata),
    do: {:ok, %{state | usage: metadata}}

  defp retirement_control?({kind, _value}) when kind in [:resumption, :go_away, :usage], do: true
  defp retirement_control?(_event), do: false

  defp current_legacy_turn?(%{input_turn: turn}, turn) when is_reference(turn), do: true
  defp current_legacy_turn?(%{output: %{turn_ref: turn}}, turn) when is_reference(turn), do: true
  defp current_legacy_turn?(_state, _turn), do: false

  defp full_fence(state) do
    state = STSInput.interrupt_model(state)

    caller_turn =
      case state.caller do
        %{turn_ref: turn, ended?: false} -> turn
        _finished -> nil
      end

    with {:ok, output} <- interrupted_output(state) do
      {:ok,
       %{
         state
         | output: output,
           output_text: nil,
           audio_buffer: [],
           audio_fenced?: true,
           input_turn: caller_turn,
           input_text: nil,
           input_ended?: false,
           generation_pending_done?: false
       }}
    end
  end

  defp interrupted_output(%{output: nil}), do: {:ok, nil}
  defp interrupted_output(%{output: %{completed_emitted?: true} = output}), do: {:ok, output}

  defp interrupted_output(%{output: %{awaiting: nil} = output} = state) do
    case Event.emit(state.channel, :output_completed,
           turn_ref: output.turn_ref,
           request_ref: output.output_ref
         ) do
      :ok ->
        {:ok,
         %{output | queue: [], interrupted?: true, completed_emitted?: true, awaiting: :completed}}

      _failure ->
        {:error, :session_failed}
    end
  end

  defp interrupted_output(%{output: output}),
    do: {:ok, %{output | queue: [], interrupted?: true}}

  defp send_tool_response(state, id, name, result) do
    with {:ok, payload} <- STS.encode_tool_result(id, name, result),
         :ok <- state.wire_module.send_control(state.wire, payload) do
      :ok
    else
      _failure -> {:error, :invalid_tool_result}
    end
  end
end
