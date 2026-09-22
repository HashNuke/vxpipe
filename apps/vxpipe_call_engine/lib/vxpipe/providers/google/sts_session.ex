defmodule Vxpipe.Providers.Google.STSSession do
  @moduledoc """
  Gemini 3.8 Live speech-to-speech adapter behind the credentialed boundary.

  Ordinary tests use fixture payloads and fake sockets; no network account is
  needed. The manifest does NOT advertise `:sts` and the hosted selection stays
  gated until the explicitly authorized interoperability check passes. See
  `Vxpipe.Providers.Google.STS` for the fixture wire assumptions.
  """

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, SessionTree, STSProvider}
  alias Vxpipe.Providers.Google.{STS, STSResumption, STSSocket}

  @setup_timeout 15_000
  @default_renew_after 420_000
  @default_expire_after 570_000
  import Vxpipe.Providers.Google.STSOutput,
    only: [
      buffer_audio: 2,
      buffer_transcript: 2,
      publish_transcript: 1,
      open_output: 3,
      mark_generation_done: 1,
      drain_output: 1
    ]

  @maximum_pending_tools 16

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
    :pending_monitor,
    :pending_handle,
    :resume_attempt,
    :resume_timer,
    :renew_timer,
    :expire_timer,
    :expire_deadline,
    :renew_after,
    :expire_after,
    :resumption_timeout_ms,
    :resume_deadline,
    ready?: false,
    renew_requested?: false,
    resuming?: false,
    resumption_handle: nil,
    input_turn: nil,
    input_text: nil,
    input_ended?: false,
    audio_fenced?: false,
    generation_pending_done?: false,
    model_turn_complete?: true,
    resumption_ambiguous?: false,
    output: nil,
    output_text: nil,
    audio_buffer: [],
    pending_tools: %{},
    usage: nil
  ]

  @impl true
  def configure(options) do
    with {:ok, public} <- STS.public_options(options) do
      Descriptor.new(
        kind: :sts,
        settings: public,
        input_format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: public.input_sample_rate,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: public.output_sample_rate,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{provider: :google, model: public.model, provenance: :provider_reported},
        readiness: :provider_acknowledged,
        endpointing:
          if(public.turn_control == "external", do: :external, else: :provider_semantic),
        speech_start?: public.turn_control != "external",
        turn_control: public.turn_control,
        turn_control_supported: ["provider", "external", "hybrid"],
        input_transcript?: true,
        output_transcript?: true,
        output_settlement: :generation_boundary,
        history_reconciliation?: false
      )
    end
  end

  @impl true
  def start_link(options), do: STSProvider.start_link(__MODULE__, options)

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
    allocation = Keyword.fetch!(options, :allocation)
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    wire_module = Keyword.get(private, :wire_module, STSSocket)
    wire_options = Keyword.get(private, :wire_options, [])
    renew_after = Keyword.get(private, :renew_after_ms, @default_renew_after)
    expire_after = Keyword.get(private, :expire_after_ms, @default_expire_after)
    resume_timeout = Keyword.get(private, :resumption_timeout_ms, 5_000)

    with :ok <- STS.validate(config),
         {:ok, expected} <-
           configure(model: config.model, voice: config.voice, turn_control: config.turn_control),
         true <- descriptor == expected,
         true <- is_atom(wire_module) and is_list(wire_options) and Keyword.keyword?(wire_options),
         true <- STSResumption.valid_deadlines?(renew_after, expire_after, resume_timeout),
         :ok <- Channel.bind(channel) do
      {:ok,
       %__MODULE__{
         channel: channel,
         socket_supervisor: SessionTree.providers(allocation),
         config: config,
         wire_module: wire_module,
         wire_options: wire_options,
         renew_after: renew_after,
         expire_after: expire_after,
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
  def handle_call(command, _from, %{renew_requested?: true, input_turn: nil, output: nil} = state)
      when is_tuple(command) and elem(command, 0) in [:push_audio, :push_text, :input_activity] do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:push_audio, audio}, _from, %{ready?: true} = state) do
    with {:ok, _encoded} <- STS.encode_audio(audio),
         :ok <- state.wire_module.send_audio(state.wire, audio) do
      {:reply, :ok, STSResumption.invalidate(state)}
    else
      {:error, :invalid_audio} -> {:reply, {:error, :session_failed}, state}
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:push_audio, _audio}, _from, state),
    do: {:reply, {:error, :session_failed}, state}

  def handle_call({:push_text, reference, text}, _from, %{ready?: true} = state) do
    turn = make_ref()

    with {:ok, _encoded} <- STS.encode_text(text),
         :ok <- state.wire_module.send_text(state.wire, text),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :provider_reported
           ),
         {:ok, state} <-
           open_text_turn(
             STSResumption.begin_turn(%{
               state
               | input_turn: turn,
                 input_text: text
             })
           ) do
      {:reply, :ok, state}
    else
      {:error, :invalid_text} -> {:reply, {:error, :invalid_text}, state}
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:push_text, _reference, _text}, _from, state),
    do: {:reply, {:error, :session_failed}, state}

  def handle_call(
        {:input_activity, _boundary},
        _from,
        %{config: %{turn_control: "provider"}} = state
      ),
      do: {:reply, {:error, :unsupported_operation}, state}

  def handle_call({:input_activity, boundary}, _from, %{ready?: true} = state)
      when boundary in [:started, :ended] do
    with :ok <- state.wire_module.send_activity(state.wire, boundary) do
      {:reply, :ok, activity_boundary(boundary, STSResumption.invalidate(state))}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:input_activity, _boundary}, _from, state),
    do: {:reply, {:error, :session_failed}, state}

  def handle_call({:interrupt, turn_ref}, _from, state) when is_reference(turn_ref) do
    if state.wire, do: state.wire_module.send_interrupt(state.wire)
    {:reply, :ok, fence_local_output(STSResumption.invalidate(state), turn_ref)}
  end

  def handle_call({:send_tool_result, call_ref, result}, _from, state)
      when is_reference(call_ref) do
    case Map.fetch(state.pending_tools, call_ref) do
      {:ok, %{id: id, name: name}} ->
        case send_tool_response(state, id, name, result) do
          :ok ->
            {:reply, :ok,
             STSResumption.invalidate(%{
               state
               | pending_tools: Map.delete(state.pending_tools, call_ref)
             })}

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
  def handle_info({:vxpipe_sts_transport, wire, {:message, payload}}, %{wire: wire} = state) do
    case STS.decode(payload) do
      {:ok, events} ->
        case apply_wire_events(events, state) do
          {:ok, state} -> {:noreply, STSResumption.advance(state)}
          {:error, _reason} -> {:stop, {:shutdown, :session_failed}, state}
        end

      {:error, :provider_failure} ->
        {:stop, {:shutdown, :session_failed}, state}

      {:error, _reason} ->
        {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {:vxpipe_sts_transport, wire, {:message, payload}},
        %{pending_wire: wire} = state
      ) do
    with {:ok, events} <- STS.decode(payload),
         true <- Enum.member?(events, :ready),
         {:ok, state} <- apply_wire_events(events -- [:ready], STSResumption.complete(state)) do
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
        {:vxpipe_sts_transport, wire, {:closed, _reason}},
        %{pending_wire: wire} = state
      ),
      do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info({:vxpipe_sts_transport, wire, {:closed, _reason}}, %{wire: wire} = state),
    do: recover_connection(state)

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{pending_monitor: monitor, pending_wire: wire} = state
      ),
      do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{wire_monitor: monitor, wire: wire} = state
      ),
      do: recover_connection(state)

  def handle_info(:setup_timeout, %{ready?: false} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info({:renew, wire}, %{wire: wire, ready?: true} = state),
    do: {:noreply, STSResumption.request(state)}

  def handle_info({:resumption_timeout, attempt}, %{resume_attempt: attempt} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info({:expire, wire}, %{wire: wire} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(:resumption_unsafe, state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info({:vxpipe_speech_output, channel, turn_ref, output_ref}, state)
      when is_reference(turn_ref) and is_reference(output_ref) do
    if channel == state.channel and turn_ref == state.input_turn do
      with {:ok, state} <- publish_transcript(open_output(state, turn_ref, output_ref)),
           {:ok, state} <- drain_output(state) do
        {:noreply, state}
      else
        {:error, _reason} -> {:stop, {:shutdown, :session_failed}, state}
      end
    else
      {:noreply, state}
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
        %{channel: channel, output: %{turn_ref: turn, output_ref: ref}} = state
      ) do
    state = %{state | output: nil, output_text: nil}

    state =
      if state.input_turn == turn,
        do: %{state | input_turn: nil, input_text: nil, input_ended?: false},
        else: state

    {:noreply, STSResumption.advance(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

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
          _conversation_event -> STSResumption.invalidate(state)
        end

      case apply_wire_event(event, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp apply_wire_event(:ready, %{ready?: false} = state) do
    Process.cancel_timer(state.setup_timer)

    with :ok <- Event.emit(state.channel, :ready, readiness: :provider_acknowledged) do
      {:ok, STSResumption.schedule_renewal(%{state | ready?: true, setup_timer: nil})}
    end
  end

  defp apply_wire_event(:ready, state), do: {:ok, state}

  defp apply_wire_event(:activity_start, %{config: %{turn_control: "external"}} = state),
    do: {:ok, state}

  defp apply_wire_event(:activity_start, %{input_turn: turn, input_ended?: false} = state)
       when not is_nil(turn),
       do: {:ok, state}

  defp apply_wire_event(:activity_start, state) do
    turn = make_ref()

    case Event.emit(state.channel, :speech_started, turn_ref: turn) do
      :ok ->
        {:ok,
         STSResumption.begin_turn(%{
           state
           | input_turn: turn,
             input_text: nil,
             input_ended?: false
         })}

      :discarded ->
        {:ok, state}

      _failure ->
        {:error, :session_failed}
    end
  end

  defp apply_wire_event(:activity_end, %{config: %{turn_control: "external"}} = state),
    do: {:ok, state}

  defp apply_wire_event(:activity_end, %{input_turn: nil} = state), do: {:ok, state}
  defp apply_wire_event(:activity_end, %{input_ended?: true} = state), do: {:ok, state}

  defp apply_wire_event(:activity_end, state) do
    # Activity ends the caller's turn, not its independently delivered transcript.
    case Event.emit(state.channel, :turn_ended,
           turn_ref: state.input_turn,
           text: "",
           endpointing: input_endpointing(state)
         ) do
      result when result in [:ok, :discarded] -> {:ok, %{state | input_ended?: true}}
      _failure -> {:error, :session_failed}
    end
  end

  defp apply_wire_event({:input_transcript, text}, %{input_turn: nil} = state) do
    _ = text
    {:ok, state}
  end

  defp apply_wire_event({:input_transcript, text}, state) do
    state = %{state | input_text: text}

    case Event.emit(state.channel, :input_transcript,
           turn_ref: state.input_turn,
           text: text,
           final: false
         ) do
      :ok -> {:ok, state}
      :discarded -> {:ok, state}
      _failure -> {:error, :session_failed}
    end
  end

  defp apply_wire_event({:audio, pcm}, %{audio_fenced?: true} = state) do
    _ = pcm
    {:ok, state}
  end

  defp apply_wire_event({:audio, pcm}, %{output: %{interrupted?: true}} = state) do
    _ = pcm
    {:ok, state}
  end

  defp apply_wire_event({:audio, pcm}, %{input_turn: nil} = state) do
    _ = pcm
    {:ok, state}
  end

  defp apply_wire_event({:audio, pcm}, state) do
    if byte_size(pcm) > 0 and rem(byte_size(pcm), 2) == 0 do
      with {:ok, state} <- buffer_audio(state, pcm),
           {:ok, state} <- drain_output(state) do
        {:ok, state}
      end
    else
      {:error, :session_failed}
    end
  end

  defp apply_wire_event({:output_transcript, text}, %{input_turn: nil} = state) do
    _ = text
    {:ok, state}
  end

  defp apply_wire_event({:output_transcript, text}, state), do: buffer_transcript(state, text)

  defp apply_wire_event(:generation_complete, state) do
    drain_output(mark_generation_done(state))
  end

  defp apply_wire_event(:turn_complete, state), do: {:ok, %{state | model_turn_complete?: true}}

  defp apply_wire_event(:interrupted, %{input_turn: nil} = state), do: {:ok, state}

  defp apply_wire_event(:interrupted, state) do
    turn = state.input_turn

    case Event.emit(state.channel, :interrupted, turn_ref: turn) do
      :ok -> {:ok, full_fence(state)}
      :discarded -> {:ok, full_fence(state)}
      _failure -> {:error, :session_failed}
    end
  end

  defp apply_wire_event({:tool_call, id, name, args}, state) do
    if map_size(state.pending_tools) >= @maximum_pending_tools do
      {:error, :session_failed}
    else
      call_ref = make_ref()
      turn = state.input_turn

      case Event.emit(state.channel, :tool_call,
             call_ref: call_ref,
             turn_ref: turn,
             tool_name: name,
             arguments: args
           ) do
        :ok ->
          {:ok,
           %{
             state
             | pending_tools:
                 Map.put(state.pending_tools, call_ref, %{id: id, name: name, turn_ref: turn})
           }}

        :discarded ->
          {:ok, state}

        _failure ->
          {:error, :session_failed}
      end
    end
  end

  defp apply_wire_event({:tool_cancel, id}, state) do
    case Enum.find(state.pending_tools, fn {_call, tool} -> tool.id == id end) do
      {call_ref, _tool} ->
        case Event.emit(state.channel, :tool_cancelled, call_ref: call_ref) do
          :ok -> {:ok, %{state | pending_tools: Map.delete(state.pending_tools, call_ref)}}
          :discarded -> {:ok, %{state | pending_tools: Map.delete(state.pending_tools, call_ref)}}
          _failure -> {:error, :session_failed}
        end

      nil ->
        {:ok, state}
    end
  end

  defp apply_wire_event({:go_away, remaining_ms}, state),
    do: {:ok, STSResumption.request(state, remaining_ms)}

  defp apply_wire_event({:resumption, handle}, state),
    do: {:ok, %{state | resumption_handle: handle}}

  defp apply_wire_event({:usage, metadata}, state) when is_map(metadata),
    do: {:ok, %{state | usage: metadata}}

  defp open_text_turn(state) do
    case Event.emit(state.channel, :turn_ended,
           turn_ref: state.input_turn,
           text: state.input_text,
           endpointing: input_endpointing(state)
         ) do
      :ok -> {:ok, %{state | input_ended?: true}}
      :discarded -> {:ok, %{state | input_ended?: true}}
      _failure -> {:error, :session_failed}
    end
  end

  defp activity_boundary(:started, %{input_turn: turn, input_ended?: false} = state)
       when not is_nil(turn),
       do: state

  defp activity_boundary(:started, state),
    do:
      STSResumption.begin_turn(%{
        state
        | input_turn: state.input_turn || make_ref(),
          input_ended?: false
      })

  defp activity_boundary(:ended, %{input_turn: nil} = state), do: state

  defp activity_boundary(:ended, state) do
    text = state.input_text || ""

    case Event.emit(state.channel, :turn_ended,
           turn_ref: state.input_turn,
           text: text,
           endpointing: :external
         ) do
      :ok -> %{state | input_ended?: true}
      :discarded -> %{state | input_ended?: true}
      _failure -> state
    end
  end

  defp input_endpointing(%{config: %{turn_control: "external"}}), do: :external
  defp input_endpointing(_state), do: :provider_semantic

  defp fence_turn(state, turn_ref) do
    output =
      case state.output do
        %{turn_ref: ^turn_ref} -> nil
        other -> other
      end

    %{state | output: output, output_text: nil, audio_buffer: [], audio_fenced?: true}
  end

  defp fence_local_output(state, turn_ref) do
    case state.output do
      %{turn_ref: ^turn_ref} = output ->
        output = %{output | queue: [], interrupted?: true}
        state = %{state | output: output, output_text: nil, audio_buffer: [], audio_fenced?: true}

        if not output.completed_emitted? and is_nil(output.awaiting) do
          _ =
            Event.emit(state.channel, :output_completed,
              turn_ref: turn_ref,
              request_ref: output.output_ref
            )

          %{state | output: nil}
        else
          state
        end

      _other ->
        fence_turn(state, turn_ref)
    end
  end

  defp full_fence(state) do
    %{
      state
      | output: nil,
        output_text: nil,
        audio_buffer: [],
        audio_fenced?: false,
        input_turn: nil,
        input_text: nil,
        input_ended?: false,
        generation_pending_done?: false
    }
  end

  defp send_tool_response(state, id, name, result) do
    with {:ok, payload} <- STS.encode_tool_result(id, name, result),
         :ok <- state.wire_module.send_control(state.wire, payload) do
      :ok
    else
      _failure -> {:error, :invalid_tool_result}
    end
  end
end
