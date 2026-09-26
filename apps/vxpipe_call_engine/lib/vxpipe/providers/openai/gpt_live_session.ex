defmodule Vxpipe.Providers.OpenAI.GPTLiveSession do
  @moduledoc "GPT-Live's scoped speech session."

  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Speech.Duplex.{
    BurstResponses,
    OutputSegmenter,
    PublishedHistory,
    TurnInference
  }

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, SessionTree, STSProvider}

  alias Vxpipe.Providers.OpenAI.{
    GPTLive,
    GPTLiveDelegation,
    GPTLiveOutput,
    GPTLiveSocket,
    GPTLiveUsage
  }

  @setup_timeout 15_000
  @reseed_timeout 5_000
  @close_timeout 10_000

  @derive {Inspect, only: [:ready?, :held?]}
  defstruct [
    :channel,
    :config,
    :socket_supervisor,
    :wire,
    :wire_monitor,
    :wire_module,
    :wire_options,
    :setup_timer,
    :close_timer,
    :session_id,
    :inference,
    :segmenter,
    :retired_segmenter,
    :bursts,
    :delegation,
    :usage,
    :history,
    :output_gap_ms,
    :output_timer,
    :output_generation,
    :pending_hold,
    :reseed_timer,
    segments: %{},
    input_ms: 0,
    ready?: false,
    held?: false,
    reseed_attempted?: false,
    resume_after_reseed?: false,
    unanswered?: false,
    latest_context: nil
  ]

  @impl true
  def configure(options) do
    with {:ok, public} <- GPTLive.public_options(options) do
      Descriptor.new(
        kind: :sts,
        settings: public,
        input_format: GPTLive.pcm_format(),
        format: GPTLive.pcm_format(),
        usage_identity: %{
          provider: :openai,
          model: public.model,
          provenance: :provider_reported
        },
        readiness: :provider_acknowledged,
        endpointing: :inferred_gap,
        speech_start?: true,
        response_start?: true,
        turn_control: "provider",
        turn_control_supported: ["provider"],
        input_transcript?: true,
        output_transcript?: true,
        output_settlement: :transcript_end,
        history_reconciliation?: false,
        output_shape: :continuous,
        barge_in: :provider,
        continuity: :history_reseed,
        tool_cancellation?: false,
        hold: :mute
      )
    end
  end

  @impl true
  def start_link(options), do: STSProvider.start_link(__MODULE__, options)

  @impl true
  def push_audio(_pid, _audio), do: {:error, :unsupported_operation}

  @impl true
  def push_text(_pid, _reference, _text), do: {:error, :unsupported_operation}

  @impl true
  def input_activity(_pid, _boundary), do: {:error, :unsupported_operation}

  @impl true
  def submit_input(pid, context, operation) when is_reference(context),
    do: GenServer.call(pid, {:submit_input, context, operation}, 5_000)

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
  def send_tool_result(pid, call_ref, result) when is_reference(call_ref),
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
    allocation = Keyword.fetch!(options, :allocation)
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    wire_module = Keyword.get(private, :wire_module, GPTLiveSocket)
    wire_options = Keyword.get(private, :wire_options, [])
    output_gap_ms = Keyword.get(private, :output_gap_ms, 800)

    with :ok <- GPTLive.validate(config),
         {:ok, expected} <-
           configure(
             model: config.model,
             voice: config.voice,
             backend_model: config.backend_model,
             input_sample_rate: config.input_sample_rate,
             output_sample_rate: config.output_sample_rate
           ),
         true <- descriptor == expected,
         true <- is_atom(wire_module) and is_list(wire_options) and Keyword.keyword?(wire_options),
         true <- is_integer(output_gap_ms) and output_gap_ms in 40..2_000,
         true <- rem(output_gap_ms, 20) == 0,
         {:ok, inference} <- TurnInference.new(),
         {:ok, segmenter} <- OutputSegmenter.new(gap_ms: output_gap_ms),
         {:ok, bursts} <- BurstResponses.new(),
         :ok <- Channel.bind(channel) do
      {:ok,
       %__MODULE__{
         channel: channel,
         config: config,
         socket_supervisor: SessionTree.providers(allocation),
         wire_module: wire_module,
         wire_options: wire_options,
         inference: inference,
         segmenter: segmenter,
         bursts: bursts,
         delegation: GPTLiveDelegation.new(),
         usage: GPTLiveUsage.new(config.backend_model),
         history: PublishedHistory.new(),
         output_gap_ms: output_gap_ms,
         output_generation: make_ref()
       }, {:continue, :connect}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    connect(state, [])
  end

  defp connect(state, history) do
    options = [
      owner: self(),
      connection: GPTLive.connection_options(state.config),
      transport_options: state.wire_options
    ]

    child = %{
      id: state.wire_module,
      start: {state.wire_module, :start_link, [options]},
      restart: :temporary,
      shutdown: :brutal_kill
    }

    with {:ok, wire} <- DynamicSupervisor.start_child(state.socket_supervisor, child),
         :ok <- send_control(state, wire, GPTLive.start(state.config, history)) do
      timeout = if state.reseed_attempted?, do: @reseed_timeout, else: @setup_timeout
      timer = Process.send_after(self(), {:setup_timeout, wire}, timeout)
      {:noreply, %{state | wire: wire, wire_monitor: Process.monitor(wire), setup_timer: timer}}
    else
      _failure -> {:stop, {:shutdown, failure_reason(state)}, state}
    end
  end

  @impl true
  def handle_call({:submit_input, _context, _operation}, _from, %{ready?: false} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:submit_input, _context, _operation}, _from, %{held?: true} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:submit_input, context, {:audio, pcm}}, _from, state) do
    with {:ok, command} <- GPTLive.audio_append(pcm),
         :ok <- send_control(state, state.wire, command) do
      {bursts, []} = BurstResponses.input_accepted(state.bursts, context)
      duration = div(byte_size(pcm) * 1_000, 48_000)
      {inference, events} = TurnInference.audio_pushed(state.inference, duration)

      state = %{
        state
        | latest_context: context,
          bursts: bursts,
          inference: inference,
          input_ms: state.input_ms + duration,
          unanswered?: state.unanswered? or ended_turn?(events)
      }

      case emit_events(state, events) do
        :ok -> {:reply, :ok, state}
        _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
      end
    else
      _failure -> {:reply, {:error, :session_failed}, state}
    end
  end

  def handle_call({:submit_input, context, {:text, reference, text}}, _from, state)
      when is_reference(reference) do
    with {:ok, command} <- GPTLive.commentary(text),
         :ok <- send_control(state, state.wire, command),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :locally_measured
           ) do
      {bursts, []} = BurstResponses.input_accepted(state.bursts, context)
      {:reply, :ok, %{state | latest_context: context, bursts: bursts, unanswered?: true}}
    else
      _failure -> {:reply, {:error, :session_failed}, state}
    end
  end

  def handle_call({:submit_input, _context, _operation}, _from, state),
    do: {:reply, {:error, :unsupported_operation}, state}

  def handle_call(:input_quiescent?, _from, state),
    do: {:reply, state.ready? and TurnInference.status(state.inference) == :idle, state}

  def handle_call({:append_history, {role, text} = entry}, _from, state)
      when role in [:caller, :agent] and is_binary(text) and byte_size(text) > 0 do
    {:reply, :ok, %{state | history: PublishedHistory.append(state.history, entry)}}
  end

  def handle_call({:append_history, _entry}, _from, state),
    do: {:reply, {:error, :invalid_history}, state}

  def handle_call({:set_input_hold, _held?}, _from, %{pending_hold: pending} = state)
      when not is_nil(pending),
      do: {:reply, {:error, :busy}, state}

  def handle_call({:set_input_hold, held?}, _from, %{held?: held?} = state),
    do: {:reply, :ok, state}

  def handle_call({:set_input_hold, held?}, from, state) do
    event_id = "hold_" <> Integer.to_string(System.unique_integer([:positive]))
    command = Map.put(GPTLive.hold(held?), "event_id", event_id)

    case send_control(state, state.wire, command) do
      :ok ->
        timer = Process.send_after(self(), {:hold_timeout, event_id}, 4_000)

        {:noreply,
         %{state | pending_hold: %{from: from, held?: held?, event_id: event_id, timer: timer}}}

      _failure ->
        {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:interrupt, turn_ref}, _from, state) do
    case GPTLiveOutput.interrupt(state, turn_ref) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:tool_result, call_ref, result}, _from, state) do
    case send_tool_result_command(state, call_ref, result) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, :stale_request} -> {:reply, {:error, :stale_request}, state}
      {:error, reason} -> {:stop, {:shutdown, reason}, {:error, reason}, state}
    end
  end

  def handle_call(:close, _from, state) do
    case send_control(state, state.wire, GPTLive.close()) do
      :ok ->
        timer = Process.send_after(self(), :close_timeout, @close_timeout)
        {:reply, :ok, %{state | close_timer: timer}}

      _failure ->
        {:stop, :normal, :ok, state}
    end
  end

  @impl true
  def handle_info({:vxpipe_sts_transport, wire, {:message, payload}}, %{wire: wire} = state) do
    case GPTLive.decode(payload) do
      {:ok, {:started, id}} when not state.ready? ->
        started(state, id)

      {:ok, {:closed, reason, usage}} ->
        closed_with_usage(state, reason, usage)

      {:ok, {:voice_usage, seconds}} ->
        voice_usage(state, seconds)

      {:ok, {:input_fragment, fragment}} ->
        {inference, events} = TurnInference.input_fragment(state.inference, fragment)

        state = %{
          state
          | inference: inference,
            unanswered?: state.unanswered? or ended_turn?(events)
        }

        case emit_events(state, events) do
          :ok -> {:noreply, state}
          _failure -> {:stop, {:shutdown, :session_failed}, state}
        end

      {:ok, {:output_fragment, fragment}} ->
        output_result(GPTLiveOutput.fragment(state, fragment))

      {:ok, {:output_audio, pcm}} ->
        output_audio(state, pcm)

      {:ok, {:delegation, id, target, response_id}} ->
        case GPTLiveDelegation.created(
               state.delegation,
               id,
               target,
               response_id,
               state.latest_context
             ) do
          {:ok, delegation} -> {:noreply, %{state | delegation: delegation}}
          {:error, reason} -> {:stop, {:shutdown, reason}, state}
        end

      {:ok, {:response_event, id, event}} ->
        response_event(state, id, event)

      {:ok, {:error, error}} ->
        if fatal_error?(error),
          do: {:stop, {:shutdown, :provider_failure}, state},
          else: {:noreply, state}

      {:ok, {:acknowledged, type, event_id}} ->
        acknowledge_hold(state, type, event_id)

      {:ok, _event} ->
        {:noreply, state}

      {:error, _reason} ->
        {:stop, {:shutdown, :invalid_message}, state}
    end
  end

  def handle_info({:vxpipe_sts_transport, wire, {:closed, reason}}, %{wire: wire} = state),
    do: closed(state, Atom.to_string(reason))

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{wire_monitor: monitor, wire: wire} = state
      ),
      do: closed(state, "connection_lost")

  def handle_info({:vxpipe_speech_output, _channel, turn_ref, output_ref}, state)
      when is_reference(turn_ref) and is_reference(output_ref),
      do: output_result(GPTLiveOutput.admitted(state, turn_ref, output_ref))

  def handle_info({:vxpipe_speech_response_discard, _channel, turn_ref}, state)
      when is_reference(turn_ref),
      do: output_result(GPTLiveOutput.discarded(state, turn_ref))

  def handle_info({:vxpipe_speech_credit, _channel, output_ref, credit, :ok}, state),
    do: {:noreply, GPTLiveOutput.credit(state, output_ref, credit)}

  def handle_info({:setup_timeout, wire}, %{wire: wire, ready?: false} = state),
    do: {:stop, {:shutdown, failure_reason(state)}, state}

  def handle_info(:reseed_deadline, %{ready?: false, reseed_attempted?: true} = state),
    do: {:stop, {:shutdown, :reseed_failed}, state}

  def handle_info(
        {:hold_timeout, event_id},
        %{pending_hold: %{event_id: event_id} = pending} = state
      ) do
    GenServer.reply(pending.from, {:error, :session_failed})
    {:stop, {:shutdown, :hold_timeout}, %{state | pending_hold: nil}}
  end

  def handle_info({:output_idle, generation}, %{output_generation: generation} = state) do
    state = %{state | output_timer: nil}

    if OutputSegmenter.burst?(state.segmenter) do
      silence = :binary.copy(<<0, 0>>, div(state.output_gap_ms * 24_000, 1_000))
      output_result(GPTLiveOutput.push_pcm(state, silence))
    else
      {:noreply, state}
    end
  end

  def handle_info(:close_timeout, state), do: {:stop, :normal, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :gpt_live_session)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp send_control(state, wire, command) do
    state.wire_module.send_control(wire, JSON.encode!(command))
  end

  defp started(state, id) do
    _ = Process.cancel_timer(state.setup_timer)

    if state.reseed_attempted? do
      if state.reseed_timer, do: Process.cancel_timer(state.reseed_timer)
      state = %{state | ready?: true, session_id: id, setup_timer: nil, reseed_timer: nil}

      if state.resume_after_reseed? do
        with {:ok, command} <-
               GPTLive.commentary(
                 "The line cut out briefly. Continue from the last thing the caller heard."
               ),
             :ok <- send_control(state, state.wire, command) do
          {:noreply, %{state | resume_after_reseed?: false}}
        else
          _failure -> {:stop, {:shutdown, :reseed_failed}, state}
        end
      else
        {:noreply, state}
      end
    else
      case Event.emit(state.channel, :ready, readiness: :provider_acknowledged) do
        :ok -> {:noreply, %{state | ready?: true, session_id: id, setup_timer: nil}}
        _failure -> {:stop, {:shutdown, :session_failed}, state}
      end
    end
  end

  defp voice_usage(state, seconds) do
    case GPTLiveUsage.voice(state.usage, seconds) do
      {:ok, usage, 0} ->
        {:noreply, %{state | usage: usage}}

      {:ok, usage, delta} ->
        case Event.emit(state.channel, :provider_usage,
               usage: %{kind: :voice, milliseconds: delta}
             ) do
          :ok -> {:noreply, %{state | usage: usage}}
          _failure -> {:stop, {:shutdown, :session_failed}, state}
        end

      {:error, reason} ->
        {:stop, {:shutdown, reason}, state}
    end
  end

  defp output_audio(state, pcm) do
    case GPTLiveOutput.push_pcm(state, pcm) do
      {:ok, next} ->
        next =
          if next.bursts.last_index > state.bursts.last_index,
            do: %{next | unanswered?: false},
            else: next

        {:noreply, schedule_output_idle(next)}

      {:error, reason, state} ->
        {:stop, {:shutdown, reason}, state}
    end
  end

  defp response_event(state, id, event) do
    with {:ok, state} <- observe_backend_usage(state, event),
         {:ok, delegation, actions} <- GPTLiveDelegation.event(state.delegation, id, event) do
      state = %{state | delegation: delegation}

      case apply_delegation_actions(state, actions) do
        {:ok, state} -> {:noreply, state}
        {:error, reason} -> {:stop, {:shutdown, reason}, state}
      end
    else
      {:error, reason} -> {:stop, {:shutdown, reason}, state}
    end
  end

  defp emit_events(state, events) do
    Enum.reduce_while(events, :ok, fn {kind, fields}, :ok ->
      case Event.emit(state.channel, kind, fields) do
        :ok -> {:cont, :ok}
        _failure -> {:halt, {:error, :session_failed}}
      end
    end)
  end

  defp output_result({:ok, state}), do: {:noreply, state}
  defp output_result({:error, reason, state}), do: {:stop, {:shutdown, reason}, state}

  defp schedule_output_idle(state) do
    if state.output_timer, do: Process.cancel_timer(state.output_timer)
    generation = make_ref()

    if OutputSegmenter.burst?(state.segmenter) do
      timer = Process.send_after(self(), {:output_idle, generation}, state.output_gap_ms)
      %{state | output_timer: timer, output_generation: generation}
    else
      %{state | output_timer: nil, output_generation: generation}
    end
  end

  defp apply_delegation_actions(state, actions) do
    Enum.reduce_while(actions, {:ok, state}, fn action, {:ok, state} ->
      case apply_delegation_action(state, action) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_delegation_action(state, {:tool_call, call_ref, name, arguments, context}) do
    turn_ref = state.inference.turn || make_ref()

    case Event.emit(state.channel, :tool_call,
           call_ref: call_ref,
           turn_ref: turn_ref,
           tool_name: name,
           arguments: arguments,
           response_context: context
         ) do
      :ok -> {:ok, state}
      :discarded -> send_tool_result_command(state, call_ref, %{"error" => "no_longer_permitted"})
      _failure -> {:error, :session_failed}
    end
  end

  defp apply_delegation_action(state, :continue) do
    case send_control(state, state.wire, GPTLive.response_create()) do
      :ok -> {:ok, state}
      _failure -> {:error, :session_failed}
    end
  end

  defp send_tool_result_command(state, call_ref, result) do
    with {:ok, delegation, call_id, continuation} <-
           GPTLiveDelegation.result(state.delegation, call_ref),
         {:ok, command} <- GPTLive.tool_output(call_id, result),
         :ok <- send_control(state, state.wire, command),
         {:ok, state} <-
           apply_delegation_actions(%{state | delegation: delegation}, continuation) do
      {:ok, state}
    else
      {:error, :stale_request} -> {:error, :stale_request}
      _failure -> {:error, :session_failed}
    end
  end

  defp observe_backend_usage(state, %{
         "type" => "response.completed",
         "response" => %{"usage" => _usage} = response
       }) do
    case GPTLiveUsage.backend(state.usage, response) do
      {:ok, usage, nil} ->
        {:ok, %{state | usage: usage}}

      {:ok, usage, report} ->
        case Event.emit(state.channel, :provider_usage, usage: Map.put(report, :kind, :backend)) do
          :ok -> {:ok, %{state | usage: usage}}
          _failure -> {:error, :session_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp observe_backend_usage(state, _event), do: {:ok, state}

  defp closed_with_usage(state, reason, nil), do: closed(state, reason)

  defp closed_with_usage(state, reason, %{"seconds" => seconds}) do
    case voice_usage(state, seconds) do
      {:noreply, state} -> closed(state, reason)
      {:stop, _reason, _state} = failed -> failed
    end
  end

  defp closed_with_usage(state, _reason, _usage),
    do: {:stop, {:shutdown, :invalid_usage}, state}

  defp closed(state, reason) when reason in ["close_requested", "remote_hangup"],
    do: {:stop, :normal, state}

  defp closed(state, "content"), do: {:stop, {:shutdown, :moderation}, state}

  defp closed(%{reseed_attempted?: false, close_timer: nil} = state, reason)
       when reason in ["expired", "connection_lost"],
       do: reseed(state)

  defp closed(%{reseed_attempted?: true} = state, _reason),
    do: {:stop, {:shutdown, :reseed_failed}, state}

  defp closed(state, _reason), do: {:stop, {:shutdown, :connection_lost}, state}

  defp reseed(state) do
    resume? = OutputSegmenter.burst?(state.segmenter) or state.unanswered?
    if state.setup_timer, do: Process.cancel_timer(state.setup_timer)
    if state.output_timer, do: Process.cancel_timer(state.output_timer)
    if state.wire_monitor, do: Process.demonitor(state.wire_monitor, [:flush])
    _ = DynamicSupervisor.terminate_child(state.socket_supervisor, state.wire)

    case GPTLiveOutput.finish(%{state | resume_after_reseed?: resume?}) do
      {:ok, state} -> reseed_after_finish(state)
      {:error, _reason, state} -> {:stop, {:shutdown, :reseed_failed}, state}
    end
  end

  defp reseed_after_finish(state) do
    {:ok, inference} = TurnInference.new()
    {:ok, segmenter} = OutputSegmenter.new(gap_ms: state.output_gap_ms)
    timer = Process.send_after(self(), :reseed_deadline, @reseed_timeout)
    resume? = state.resume_after_reseed? or state.unanswered?

    state = %{
      state
      | ready?: false,
        wire: nil,
        wire_monitor: nil,
        setup_timer: nil,
        reseed_timer: timer,
        reseed_attempted?: true,
        resume_after_reseed?: resume?,
        inference: inference,
        retired_segmenter: state.segmenter,
        segmenter: segmenter,
        delegation: GPTLiveDelegation.new(),
        usage: GPTLiveUsage.new(state.config.backend_model),
        input_ms: 0,
        output_timer: nil,
        output_generation: make_ref(),
        unanswered?: false
    }

    connect(state, PublishedHistory.input(state.history))
  end

  defp failure_reason(%{reseed_attempted?: true}), do: :reseed_failed
  defp failure_reason(_state), do: :session_failed

  defp ended_turn?(events), do: Enum.any?(events, fn {kind, _fields} -> kind == :turn_ended end)

  defp fatal_error?(error) do
    Map.get(error, "code") in [
      "invalid_request_error",
      "authentication_error",
      "permission_denied"
    ] or
      Map.get(error, "type") in ["invalid_request_error", "authentication_error"]
  end

  defp acknowledge_hold(
         %{pending_hold: %{event_id: event_id, held?: held?} = pending} = state,
         type,
         event_id
       ) do
    expected = if held?, do: "session.input_audio.muted", else: "session.input_audio.unmuted"

    if type == expected do
      Process.cancel_timer(pending.timer)

      note =
        if held?,
          do: "The caller is on hold and cannot hear you. Continue pending work quietly.",
          else:
            "The caller has returned. Nothing said during the hold was heard. Resume listening."

      with {:ok, context} <- GPTLive.thinking(note),
           :ok <- send_control(state, state.wire, context) do
        GenServer.reply(pending.from, :ok)
        {:noreply, %{state | held?: held?, pending_hold: nil}}
      else
        _failure ->
          GenServer.reply(pending.from, {:error, :session_failed})
          {:stop, {:shutdown, :session_failed}, %{state | pending_hold: nil}}
      end
    else
      {:noreply, state}
    end
  end

  defp acknowledge_hold(state, _type, _event_id), do: {:noreply, state}
end
