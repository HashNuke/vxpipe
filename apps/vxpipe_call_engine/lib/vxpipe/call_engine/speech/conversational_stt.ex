defmodule Vxpipe.CallEngine.Speech.ConversationalSTT do
  @moduledoc """
  Allocation-owned human STT composition. Native recognition events are
  acknowledged before translation to one canonical turn stream. Transcript
  onset is the default, with turn ends from the recognizer. With `vad: true`,
  Silero observes the same accepted input and owns both turn start and turn end
  through `LocalTurnEnd`; recognizer turns become segments, and recognizers
  declaring `turn_finalize?` are asked to finalize after caller silence.
  Output transcription uses the original provider directly.
  """
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, InferenceTap, ProviderTiming}

  alias Vxpipe.CallEngine.Speech.{
    ActivityBoundary,
    CapabilityTree,
    Channel,
    Descriptor,
    Event,
    LocalTurnEnd,
    Session,
    SessionTree,
    Silero.Detector,
    STTProvider,
    STTTurnStart
  }

  @maximum_pcm_bytes 96_000
  @window_bytes 1_024
  @orphan_timeout_ms 60_000
  @endpoint_hangover_ms 300
  @final_wait_ms 1_000
  @max_pending_links 4

  @impl true
  def models, do: []

  @impl true
  def configure(options) do
    with true <- Keyword.keyword?(options),
         {:ok, options} <- Keyword.validate(options, [:provider, :options, vad: false]),
         provider when is_atom(provider) and provider != __MODULE__ <-
           Keyword.fetch!(options, :provider),
         true <- Code.ensure_loaded?(provider),
         vad when is_boolean(vad) <- Keyword.fetch!(options, :vad),
         {:ok, descriptor} <- provider.configure(Keyword.fetch!(options, :options)),
         :ok <- Descriptor.validate_conversational_stt(descriptor) do
      {:ok,
       %{
         descriptor
         | settings: Map.put(descriptor.settings, :vad, vad),
           finite_input?: false,
           frame_input?: true,
           turn_finalize?: false,
           speech_start_evidence: if(vad, do: :local_acoustic, else: :transcript)
       }
       |> local_endpointing(vad)}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _error -> {:error, :invalid_configuration}
  end

  defp local_endpointing(descriptor, false), do: descriptor

  defp local_endpointing(descriptor, true),
    do: %{descriptor | endpointing: :local_gap, eager_end?: false, resume?: false}

  @impl true
  def start_link(options), do: STTProvider.start_link(__MODULE__, options)
  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:audio, audio}, 5_000)
  @impl true
  def push_frame(pid, frame), do: GenServer.call(pid, {:frame, frame}, 5_000)

  @doc false
  def observe(allocation, %CaptureHandoff{} = handoff), do: Channel.observe(allocation, handoff)

  @impl true
  def close(pid), do: GenServer.stop(pid, :normal, 5_000)

  @impl true
  def init(options) do
    allocation = Keyword.fetch!(options, :allocation)
    descriptor = Keyword.fetch!(options, :descriptor)
    private = Keyword.fetch!(options, :private)
    channel = Keyword.fetch!(options, :channel)
    boundary_timeout = Keyword.get(private, :boundary_timeout_ms, @orphan_timeout_ms)
    hangover = Keyword.get(private, :endpoint_hangover_ms, @endpoint_hangover_ms)
    final_wait = Keyword.get(private, :final_wait_ms, @final_wait_ms)
    recognizer = Keyword.fetch!(private, :recognizer)

    with {:ok, expected} <-
           configure(
             provider: Keyword.fetch!(private, :recognizer),
             options: Keyword.fetch!(private, :recognizer_options),
             vad: descriptor.settings.vad
           ),
         true <- expected == descriptor,
         {:ok, inner_descriptor} <-
           recognizer.configure(Keyword.fetch!(private, :recognizer_options)),
         true <- is_integer(boundary_timeout) and boundary_timeout in 1..@orphan_timeout_ms,
         true <- is_integer(hangover) and hangover in 1..5_000,
         true <- is_integer(final_wait) and final_wait in 1..10_000,
         :ok <- Channel.bind(channel) do
      {:ok,
       %{
         allocation: allocation,
         descriptor: descriptor,
         private: private,
         channel: channel,
         inner: nil,
         inner_frame_input?: inner_descriptor.frame_input?,
         inner_monitor: nil,
         runtime: nil,
         runtime_monitor: nil,
         inference: nil,
         diagnostic_tap: nil,
         diagnostic_handoff: nil,
         diagnostic_last_link: nil,
         diagnostic_inference: nil,
         inference_epoch: nil,
         acoustic_origin_ms: nil,
         acoustic_source: :unbound,
         acoustic_sequence: 0,
         recognition_epoch: 0,
         pending_epoch: nil,
         pending_pcm: "",
         odd_pcm: "",
         cursor: 0,
         ready?: false,
         recognizer_ready?: false,
         detector_ready?: not descriptor.settings.vad,
         stream: nil,
         boundary: nil,
         orphan: nil,
         boundary_timeout: boundary_timeout,
         ignored_refs: MapSet.new(),
         turns: STTTurnStart.new(),
         local:
           if(descriptor.settings.vad,
             do: LocalTurnEnd.new(finalize?: inner_descriptor.turn_finalize?)
           ),
         endpoint_timer: nil,
         pending_links: [],
         endpoint_hangover: hangover,
         final_wait: final_wait
       }, {:continue, :prepare}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:prepare, state) do
    private = state.private

    with {:ok, tree} <-
           DynamicSupervisor.start_child(
             SessionTree.providers(state.allocation),
             {CapabilityTree, owner: self()}
           ),
         {:ok, inner, :starting} <-
           Session.start(CapabilityTree.scope(tree),
             provider: Keyword.fetch!(private, :recognizer),
             options: Keyword.fetch!(private, :recognizer_options),
             private: Keyword.get(private, :recognizer_private, []),
             start_timeout:
               max(state.allocation.deadline - System.monotonic_time(:millisecond), 1)
           ),
         {:ok, state} <-
           prepare_detector(%{state | inner: inner, inner_monitor: Process.monitor(tree)}) do
      {:noreply, state}
    else
      _failure -> fail(state)
    end
  end

  @impl true
  def handle_call(:synchronize, _from, state), do: {:reply, :ok, state}

  def handle_call({:frame, _frame}, _from, %{ready?: false} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:frame, frame}, _from, state) do
    with {:ok, pcm, timestamp} <- frame_pcm(state, frame) do
      accept_input(state, frame.payload, pcm, timestamp, frame)
    else
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:audio, _audio}, _from, %{ready?: false} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:audio, audio}, _from, state) do
    case detector_pcm(state, audio) do
      {:ok, pcm, next} ->
        case accept_input(next, audio, pcm) do
          {:reply, {:error, :busy}, _next} -> {:reply, {:error, :busy}, state}
          result -> result
        end

      _failure ->
        {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  @impl true
  def handle_info(
        {:diagnostic_profile, generation, canonical, %CaptureHandoff{} = handoff, channel},
        state
      )
      when generation == state.allocation.generation do
    if channel == GenServer.whereis(state.channel) and state.inner != nil and
         CaptureHandoff.current?(handoff),
       do:
         Vxpipe.CallEngine.Speech.DiagnosticSubscription.request_profile(
           state.inner,
           handoff,
           canonical
         )

    {:noreply, state}
  end

  def handle_info({:diagnostic_observer, generation, %CaptureHandoff{} = handoff, channel}, state)
      when generation == state.allocation.generation do
    with true <- channel == GenServer.whereis(state.channel),
         {:ok, handoff} <- ProviderTiming.replace(state.diagnostic_handoff, handoff) do
      Channel.observe(state.inner, handoff)

      tap =
        if state.runtime != nil do
          InferenceTap.attach(
            state.diagnostic_tap,
            handoff,
            state.recognition_epoch,
            state.stream,
            state.inference != nil,
            state.pending_pcm == "" and state.odd_pcm == ""
          )
        else
          nil
        end

      last_link = if state.diagnostic_handoff == handoff, do: state.diagnostic_last_link

      {:noreply,
       %{
         state
         | diagnostic_tap: tap,
           diagnostic_handoff: handoff,
           diagnostic_last_link: last_link
       }}
    else
      _ -> {:noreply, state}
    end
  end

  def handle_info({:vxpipe_speech, %Event{session: inner} = event}, %{inner: inner} = state) do
    with :ok <- Session.ack(inner, event),
         {:ok, state} <- recognition(state, event) do
      {:noreply, state}
    else
      _failure -> fail(state)
    end
  end

  def handle_info(
        {:silero_result, ref, {:ok, _, _}},
        %{inference: ref, detector_ready?: false} = state
      ) do
    activate(%{state | inference: nil, detector_ready?: true})
  end

  def handle_info({:silero_result, ref, {:ok, p, packed}}, %{inference: ref} = state) do
    current? = state.inference_epoch == state.recognition_epoch
    if current?, do: InferenceTap.result(state.diagnostic_inference, [p])

    stream =
      if current?, do: %{packed: packed, samples: state.stream.samples + 512}, else: state.stream

    state = %{state | stream: stream, inference: nil, diagnostic_inference: nil}

    with {:ok, state} <- probabilities(state, [p], current?),
         {:ok, state} <- advance_detector(state) do
      {:noreply, state}
    else
      _ -> fail(state)
    end
  end

  def handle_info({:silero_retired, ref}, %{inference: ref} = state) do
    case advance_detector(%{state | inference: nil, diagnostic_inference: nil}) do
      {:ok, next} -> {:noreply, next}
      _ -> fail(state)
    end
  end

  def handle_info(
        {:silero_result, ref, {:error, :classification_timeout, :await_settlement}},
        %{inference: ref, detector_ready?: true} = state
      )
      when state.inference_epoch != state.recognition_epoch do
    {:noreply, state}
  end

  def handle_info({:silero_result, ref, _failure}, %{inference: ref} = state) do
    if state.detector_ready? and state.inference_epoch != state.recognition_epoch do
      handle_info({:silero_retired, ref}, state)
    else
      InferenceTap.failed(state.diagnostic_inference)
      fail(state)
    end
  end

  def handle_info({:orphan, token}, %{orphan: {_timer, token}} = state), do: fail(state)

  def handle_info({:local_endpoint, phase, token}, %{endpoint_timer: {_timer, token}} = state) do
    elapsed =
      if phase == :hangover,
        do: LocalTurnEnd.hangover_elapsed(state.local),
        else: LocalTurnEnd.final_wait_elapsed(state.local)

    case local_result(%{state | endpoint_timer: nil}, elapsed) do
      {:ok, state} -> {:noreply, state}
      _failure -> fail(state)
    end
  end

  def handle_info({:DOWN, reference, :process, _pid, _reason}, state)
      when reference == state.inner_monitor or reference == state.runtime_monitor,
      do: fail(state)

  def handle_info({:vxpipe_speech_closed, inner, _reason}, %{inner: inner} = state),
    do: fail(state)

  def handle_info(_stale, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :conversational_stt)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp prepare_detector(%{detector_ready?: true} = state), do: {:ok, state}

  defp prepare_detector(state) do
    stream = Detector.stream()

    with {:ok, detector} <-
           Detector.prepare(state.allocation, Keyword.get(state.private, :activity_options, [])),
         {:ok, ref} <-
           Detector.submit(
             detector,
             stream,
             :binary.copy(<<0>>, @window_bytes),
             :warmup,
             state.allocation.deadline
           ) do
      {:ok,
       %{
         state
         | runtime: detector,
           runtime_monitor: Process.monitor(detector.lease.pool),
           inference: ref,
           stream: stream,
           boundary: ActivityBoundary.new()
       }}
    end
  end

  defp recognition(state, %Event{kind: :ready}) do
    case activate(%{state | recognizer_ready?: true}) do
      {:noreply, state} -> {:ok, state}
      _failure -> {:error, :session_failed}
    end
  end

  defp recognition(_state, %Event{kind: :failed}), do: {:error, :session_failed}

  defp recognition(state, event) do
    cond do
      MapSet.member?(state.ignored_refs, event.turn_ref) -> {:ok, state}
      not Channel.input_active?(state.channel) -> ignore_unadmitted(state, event.turn_ref)
      true -> admitted_recognition(state, event)
    end
  end

  defp ignore_unadmitted(state, reference) when is_reference(reference) do
    if MapSet.size(state.ignored_refs) < STTTurnStart.max_retired(),
      do: {:ok, %{state | ignored_refs: MapSet.put(state.ignored_refs, reference)}},
      else: {:error, :turn_overflow}
  end

  defp ignore_unadmitted(state, _reference), do: {:ok, state}

  defp admitted_recognition(%{local: nil} = state, event) do
    with {:ok, turns, emissions} <- STTTurnStart.native(state.turns, event),
         :ok <- publish(state.channel, emissions) do
      state = diagnostic_links(%{state | turns: turns}, emissions)
      {:ok, state |> settle_detector(emissions) |> update_orphan(emissions)}
    end
  end

  defp admitted_recognition(state, event) do
    with {:ok, state} <- local_result(state, LocalTurnEnd.native(state.local, event)),
         do: {:ok, local_link(state, event.turn_ref)}
  end

  # Applies one LocalTurnEnd result: publish emissions in order, then run the
  # owner actions it requested.
  defp local_result(state, {:ok, local, emissions, actions}) do
    with :ok <- publish(state.channel, emissions) do
      state = %{state | local: local}
      state = Enum.reduce(emissions, state, &local_link(&2, &1))
      Enum.reduce_while(actions, {:ok, settle_detector(state, emissions)}, &local_action/2)
    end
  end

  defp local_result(_state, _failure), do: {:error, :session_failed}

  defp local_action(:arm_hangover, {:ok, state}),
    do: {:cont, {:ok, arm_endpoint(state, :hangover, state.endpoint_hangover)}}

  defp local_action(:arm_final_wait, {:ok, state}),
    do: {:cont, {:ok, arm_endpoint(state, :final_wait, state.final_wait)}}

  defp local_action(:cancel_timers, {:ok, state}), do: {:cont, {:ok, cancel_endpoint(state)}}

  defp local_action(:finalize, {:ok, state}) do
    case Session.input_activity(state.inner, :ended) do
      :ok -> {:cont, {:ok, state}}
      {:error, :unsupported_operation} -> {:cont, {:ok, state}}
      _failure -> {:halt, {:error, :session_failed}}
    end
  end

  defp arm_endpoint(state, phase, timeout) do
    state = cancel_endpoint(state)
    token = make_ref()
    timer = Process.send_after(self(), {:local_endpoint, phase, token}, timeout)
    %{state | endpoint_timer: {timer, token}}
  end

  defp cancel_endpoint(%{endpoint_timer: nil} = state), do: state

  defp cancel_endpoint(%{endpoint_timer: {timer, _token}} = state) do
    Process.cancel_timer(timer)
    %{state | endpoint_timer: nil}
  end

  # Provider hints seen before a local turn opens are linked once it opens.
  defp local_link(state, {:speech_started, _fields}) do
    {pending, state} = {Enum.reverse(state.pending_links), %{state | pending_links: []}}
    Enum.reduce(pending, state, &local_link(&2, &1))
  end

  defp local_link(state, {_kind, _fields}), do: state

  defp local_link(%{diagnostic_handoff: nil} = state, _native), do: state

  defp local_link(state, native) when is_reference(native) do
    case LocalTurnEnd.active(state.local) do
      nil ->
        pending =
          Enum.take([native | List.delete(state.pending_links, native)], @max_pending_links)

        %{state | pending_links: pending}

      canonical ->
        offer_link(state, native, canonical)
    end
  end

  defp local_link(state, _native), do: state

  defp offer_link(state, native, canonical) do
    with packet =
           {:turn_link, state.inner.generation, native, state.allocation.generation, canonical},
         false <- packet == state.diagnostic_last_link,
         :ok <- CaptureHandoff.offer(state.diagnostic_handoff, packet) do
      %{state | diagnostic_last_link: packet}
    else
      _ -> state
    end
  end

  # A settled turn starts a new recognition epoch: in-flight detector work for
  # earlier audio cannot start or extend the next turn.
  defp settle_detector(state, emissions) do
    if Enum.any?(emissions, fn {kind, _fields} -> kind == :turn_ended end) do
      if state.inference, do: Detector.cancel(state.runtime, state.inference)

      %{
        state
        | recognition_epoch: state.recognition_epoch + 1,
          acoustic_origin_ms: nil,
          diagnostic_tap:
            InferenceTap.reset(
              state.diagnostic_tap,
              state.recognition_epoch + 1,
              state.odd_pcm == ""
            ),
          pending_pcm: "",
          pending_epoch: nil,
          stream: if(state.runtime, do: Detector.stream(), else: nil),
          boundary: if(state.runtime, do: ActivityBoundary.new(), else: nil)
      }
    else
      state
    end
  end

  defp diagnostic_links(%{diagnostic_handoff: nil} = state, _emissions), do: state

  defp diagnostic_links(state, emissions) do
    emissions
    |> Enum.map(fn {_kind, fields} -> Keyword.fetch!(fields, :turn_ref) end)
    |> then(fn references ->
      if state.turns.active, do: references ++ [state.turns.active], else: references
    end)
    |> Enum.uniq()
    |> Enum.reduce(state, fn canonical, current ->
      with {:ok, native} <- STTTurnStart.native_reference(current.turns, canonical),
           packet =
             {:turn_link, current.inner.generation, native, current.allocation.generation,
              canonical},
           false <- packet == current.diagnostic_last_link,
           :ok <- CaptureHandoff.offer(current.diagnostic_handoff, packet) do
        %{current | diagnostic_last_link: packet}
      else
        _ -> current
      end
    end)
  end

  defp activate(%{ready?: false, recognizer_ready?: true, detector_ready?: true} = state) do
    case Event.emit(state.channel, :ready, readiness: state.descriptor.readiness) do
      :ok -> {:noreply, %{state | ready?: true}}
      :discarded -> {:noreply, %{state | ready?: true}}
      _failure -> fail(state)
    end
  end

  defp activate(state), do: {:noreply, state}

  defp frame_pcm(%{runtime: nil}, _frame), do: {:ok, "", nil}

  defp frame_pcm(_state, frame) do
    case Vxpipe.CallEngine.Speech.STTActivityPCM.normalize(frame) do
      {:ok, pcm, timestamp} -> {:ok, pcm, timestamp}
      _failure -> {:error, :unsupported_audio}
    end
  end

  defp acoustic_source(%{acoustic_source: :unbound} = state, %{source_epoch: epoch})
       when not is_nil(state.runtime) do
    send(state.allocation.consumer, {:vxpipe_acoustic_epoch, state.allocation, epoch})
    %{state | acoustic_source: epoch}
  end

  defp acoustic_source(state, %{source_epoch: epoch})
       when epoch != state.acoustic_source and not is_nil(state.runtime) do
    send(state.allocation.consumer, {:vxpipe_acoustic_epoch, state.allocation, epoch})
    if state.inference, do: Detector.cancel(state.runtime, state.inference)
    next = state.recognition_epoch + 1
    if state.orphan, do: Process.cancel_timer(elem(state.orphan, 0))

    %{
      state
      | acoustic_source: epoch,
        odd_pcm: "",
        acoustic_origin_ms: nil,
        recognition_epoch: next,
        orphan: nil,
        diagnostic_tap: InferenceTap.reset(state.diagnostic_tap, next, true),
        pending_pcm: "",
        pending_epoch: nil,
        stream: Detector.stream(),
        boundary: ActivityBoundary.new()
    }
  end

  defp acoustic_source(%{acoustic_source: :unbound} = state, nil),
    do: %{state | acoustic_source: nil}

  defp acoustic_source(state, _frame), do: state

  defp accept_input(state, audio, pcm, timestamp \\ nil, frame \\ nil) do
    in_flight_bytes = if state.inference, do: @window_bytes, else: 0

    if byte_size(state.pending_pcm) + byte_size(pcm) + byte_size(state.odd_pcm) + in_flight_bytes >
         @maximum_pcm_bytes do
      {:reply, {:error, :busy}, state}
    else
      result =
        if frame != nil and state.inner_frame_input?,
          do: Session.push_frame(state.inner, frame),
          else: Session.push_audio(state.inner, audio)

      case result do
        :ok ->
          state = acoustic_source(state, frame)

          pending_epoch =
            if state.pending_pcm == "", do: state.recognition_epoch, else: state.pending_epoch

          origin =
            if pcm != "" and is_nil(state.acoustic_origin_ms),
              do: (frame && frame.received_at) || System.monotonic_time(:millisecond),
              else: state.acoustic_origin_ms

          case advance_detector(%{
                 state
                 | acoustic_origin_ms: origin,
                   diagnostic_tap:
                     InferenceTap.accept(
                       state.diagnostic_tap,
                       state.recognition_epoch,
                       timestamp,
                       div(byte_size(pcm), 2)
                     ),
                   pending_pcm: state.pending_pcm <> pcm,
                   pending_epoch: pending_epoch
               }) do
            {:ok, next} -> {:reply, :ok, next}
            _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
          end

        {:error, :busy} ->
          {:reply, {:error, :busy}, state}

        _failure ->
          {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
      end
    end
  end

  defp detector_pcm(%{runtime: nil} = state, _audio), do: {:ok, "", state}

  defp detector_pcm(
         %{descriptor: %{format: %{encoding: :linear16, sample_rate: rate}}} = state,
         audio
       ) do
    combined = state.odd_pcm <> audio
    bytes = byte_size(combined) - rem(byte_size(combined), 2)
    <<pcm::binary-size(bytes), odd::binary>> = combined

    result =
      if pcm == "",
        do: {:ok, "", state.cursor},
        else: Vxpipe.CallEngine.Speech.STTActivityPCM.normalize_payload(pcm, state.cursor, rate)

    with {:ok, normalized, _timestamp} <- result,
         do: {:ok, normalized, %{state | cursor: state.cursor + div(bytes, 2), odd_pcm: odd}}
  end

  defp detector_pcm(_state, _audio), do: {:error, :unsupported_audio}

  defp advance_detector(%{runtime: nil} = state), do: {:ok, state}

  defp advance_detector(%{inference: reference} = state) when not is_nil(reference),
    do: {:ok, state}

  defp advance_detector(%{pending_pcm: pcm} = state) when byte_size(pcm) < @window_bytes,
    do: {:ok, state}

  defp advance_detector(state) do
    <<chunk::binary-size(@window_bytes), pending::binary>> = state.pending_pcm

    diagnostic_inference =
      InferenceTap.begin(state.diagnostic_tap, state.recognition_epoch, state.stream)

    with {:ok, reference} <-
           Detector.submit(state.runtime, state.stream, chunk, state.recognition_epoch),
         do:
           {:ok,
            %{
              state
              | inference: reference,
                diagnostic_inference: diagnostic_inference,
                inference_epoch: state.pending_epoch,
                pending_pcm: pending
            }}
  end

  defp probabilities(state, _probabilities, false), do: {:ok, state}

  defp probabilities(state, probabilities, true) do
    Enum.reduce_while(probabilities, {:ok, state}, fn probability, {:ok, current} ->
      with {:ok, boundary, events} <- ActivityBoundary.push(current.boundary, probability),
           {:ok, next} <-
             acoustic(%{current | boundary: boundary}, events) do
        {:cont, {:ok, next}}
      else
        _failure -> {:halt, {:error, :session_failed}}
      end
    end)
  end

  defp acoustic(state, events) do
    Enum.reduce_while(events, {:ok, state}, fn {kind, sample}, {:ok, current} ->
      result =
        if kind == :speech_started,
          do: LocalTurnEnd.acoustic_started(current.local),
          else: LocalTurnEnd.acoustic_ended(current.local)

      # Speech start publishes before its activity evidence; speech end reports
      # evidence for the turn before any later settlement.
      current =
        if kind == :speech_ended, do: notify_activity(current, kind, sample), else: current

      case local_result(current, result) do
        {:ok, next} ->
          next = if kind == :speech_started, do: notify_activity(next, kind, sample), else: next
          {:cont, {:ok, next}}

        _failure ->
          {:halt, {:error, :session_failed}}
      end
    end)
  end

  defp active_turn(%{local: nil} = state), do: state.turns.active
  defp active_turn(state), do: LocalTurnEnd.active(state.local)

  defp notify_activity(state, kind, sample) do
    active = active_turn(state)

    if is_reference(active) and Channel.input_active?(state.channel) do
      sequence = state.acoustic_sequence + 1

      evidence = %{
        at_ms: state.acoustic_origin_ms + div(sample * 1_000, 16_000),
        capture_origin_ms: state.acoustic_origin_ms,
        source_epoch: state.acoustic_source,
        sample_index: sample,
        sample_rate: 16_000,
        sequence: sequence
      }

      send(state.allocation.consumer, {
        :vxpipe_acoustic_activity,
        state.allocation,
        active,
        kind,
        evidence
      })

      %{state | acoustic_sequence: sequence}
    else
      state
    end
  end

  defp update_orphan(state, emissions) do
    cond do
      is_nil(state.turns.active) or match?(%{speaking?: true}, state.boundary) ->
        if state.orphan, do: Process.cancel_timer(elem(state.orphan, 0))
        %{state | orphan: nil}

      Enum.any?(emissions, fn {kind, _} -> kind in [:speech_started, :transcript] end) ->
        arm_orphan(state)

      true ->
        state
    end
  end

  defp arm_orphan(%{turns: %{active: nil}} = state), do: state

  defp arm_orphan(state) do
    if state.orphan, do: Process.cancel_timer(elem(state.orphan, 0))
    token = make_ref()
    timer = Process.send_after(self(), {:orphan, token}, state.boundary_timeout)
    %{state | orphan: {timer, token}}
  end

  defp publish(channel, emissions) do
    Enum.reduce_while(emissions, :ok, fn {kind, fields}, :ok ->
      case Event.emit(channel, kind, fields) do
        result when result in [:ok, :discarded] -> {:cont, :ok}
        _failure -> {:halt, {:error, :session_failed}}
      end
    end)
  end

  defp fail(state), do: {:stop, {:shutdown, :session_failed}, state}
end
