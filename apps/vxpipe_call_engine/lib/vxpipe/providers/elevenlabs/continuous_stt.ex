defmodule Vxpipe.Providers.ElevenLabs.ContinuousSTT do
  @moduledoc """
  Continuous Scribe recognition using upstream VAD commits. Commits are stable
  segments, including forced long-input segments. A 1.5-second absence of further
  transcript revisions after a commit, with no outstanding draft, is an inferred
  endpoint, not acoustic or provider-semantic proof. A stable draft after a committed
  segment requests one explicit flush while upstream remains in VAD mode. Committed
  text is required before settlement; missing responses fail within a bounded deadline.
  The stream lives inside one permission allocation.
  """
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, SessionTree, STTProvider}
  alias Vxpipe.Providers.ElevenLabs.{Scribe, ScribeSocket}

  @maximum_audio_bytes 96_000
  @maximum_text_bytes 65_536
  @inferred_gap_ms 1_500
  @commit_timeout_ms 60_000
  @flush_timeout_ms 5_000

  @impl true
  defdelegate models(), to: Scribe

  @impl true
  def configure(options) do
    with {:ok, public} <- Scribe.public_options(options),
         :vad <- public.commit_strategy do
      Descriptor.new(
        kind: :stt,
        settings: public,
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: 16_000,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :elevenlabs,
          model: public.model,
          provenance: :locally_measured
        },
        readiness: :provider_acknowledged,
        endpointing: :inferred_gap,
        speech_start?: true,
        speech_start_evidence: :transcript
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def start_link(options), do: STTProvider.start_link(__MODULE__, options)
  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:push_audio, audio}, 5_000)
  @impl true
  def close(pid), do: GenServer.stop(pid, :normal, 5_000)

  @impl true
  def init(options) do
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    channel = Keyword.fetch!(options, :channel)
    gap = Keyword.get(private, :inferred_gap_ms, @inferred_gap_ms)
    commit_timeout = Keyword.get(private, :commit_timeout_ms, @commit_timeout_ms)
    flush_timeout = Keyword.get(private, :flush_timeout_ms, @flush_timeout_ms)

    with %Scribe{commit_strategy: :vad} <- config,
         {:ok, descriptor} <-
           configure(
             Map.to_list(
               Map.take(
                 config,
                 [:model, :encoding, :sample_rate, :language_code, :commit_strategy]
               )
             )
           ),
         true <- descriptor == Keyword.fetch!(options, :descriptor),
         true <- is_integer(gap) and gap in 1..5_000,
         true <- is_integer(commit_timeout) and commit_timeout in 1..@commit_timeout_ms,
         true <- is_integer(flush_timeout) and flush_timeout in 1..@flush_timeout_ms,
         :ok <- Channel.bind(channel) do
      {:ok,
       %{
         allocation: Keyword.fetch!(options, :allocation),
         channel: channel,
         config: config,
         wire_module: Keyword.get(private, :wire_module, ScribeSocket),
         wire_options: Keyword.get(private, :wire_options, []),
         wire: nil,
         monitor: nil,
         ready?: false,
         request_id: nil,
         turn: nil,
         committed: "",
         partial: "",
         last_text: "",
         accepted_samples: 0,
         settled_samples: 0,
         candidate: nil,
         commit_watchdog: nil,
         commit_timeout: commit_timeout,
         flush: nil,
         flush_timeout: flush_timeout,
         gap: gap
       }, {:continue, :connect}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    options = [
      owner: self(),
      connection: Scribe.connection_options(state.config),
      commit_strategy: :vad,
      transport_options: state.wire_options
    ]

    child = %{
      id: state.wire_module,
      start: {state.wire_module, :start_link, [options]},
      restart: :temporary,
      shutdown: :brutal_kill
    }

    case DynamicSupervisor.start_child(SessionTree.providers(state.allocation), child) do
      {:ok, wire} -> {:noreply, %{state | wire: wire, monitor: Process.monitor(wire)}}
      _failure -> fail(state)
    end
  end

  @impl true
  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  def handle_call({:push_audio, audio}, _from, %{ready?: true} = state)
      when is_binary(audio) and byte_size(audio) in 2..@maximum_audio_bytes and
             rem(byte_size(audio), 2) == 0 do
    case forward(state, audio) do
      :ok ->
        {:reply, :ok,
         %{state | accepted_samples: state.accepted_samples + div(byte_size(audio), 2)}}

      _failure ->
        {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:push_audio, _audio}, _from, state),
    do: {:reply, {:error, :session_failed}, state}

  @impl true
  def handle_info(
        {:vxpipe_scribe_transport, wire, {:event, {:ready, request_id}}},
        %{wire: wire, ready?: false} = state
      ) do
    case Event.emit(state.channel, :ready, readiness: :provider_acknowledged) do
      result when result in [:ok, :discarded] ->
        {:noreply, %{state | ready?: true, request_id: request_id}}

      _failure ->
        fail(state)
    end
  end

  def handle_info(
        {:vxpipe_scribe_transport, wire, {:event, {kind, text}}},
        %{wire: wire, ready?: true} = state
      )
      when kind in [:partial, :segment] and is_binary(text) do
    case recognition(state, kind, text) do
      {:ok, state} -> {:noreply, state}
      _failure -> fail(state)
    end
  end

  def handle_info({:inferred_endpoint, token}, %{candidate: {_timer, token}} = state) do
    duration = div((state.accepted_samples - state.settled_samples) * 1_000, 16_000)

    case Event.emit(state.channel, :turn_ended,
           turn_ref: state.turn,
           text: state.last_text,
           endpointing: :inferred_gap,
           provider_request_id: state.request_id,
           audio_duration_ms: duration
         ) do
      result when result in [:ok, :discarded] ->
        {:noreply,
         %{
           cancel_commit_watchdog(state)
           | turn: nil,
             committed: "",
             partial: "",
             last_text: "",
             candidate: nil,
             settled_samples: state.accepted_samples
         }}

      _failure ->
        fail(state)
    end
  end

  def handle_info({:commit_deadline, token}, %{commit_watchdog: {_timer, token}} = state),
    do: fail(state)

  def handle_info({:flush_draft, token}, %{flush: {:gap, _timer, token}} = state) do
    case request_commit(state) do
      :ok ->
        token = make_ref()
        timer = Process.send_after(self(), {:flush_expired, token}, state.flush_timeout)
        {:noreply, %{state | flush: {:commit, timer, token}}}

      _failure ->
        fail(state)
    end
  end

  def handle_info({:flush_expired, token}, %{flush: {:commit, _timer, token}} = state),
    do: fail(state)

  def handle_info({:vxpipe_scribe_transport, wire, _failure}, %{wire: wire} = state),
    do: fail(state)

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state),
    do: fail(state)

  def handle_info(_stale, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :continuous_scribe)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp recognition(state, :partial, text) do
    if String.trim(text) == "" or text == state.partial do
      {:ok, state}
    else
      state = state |> cancel_candidate() |> cancel_flush_candidate()

      with {:ok, state} <- publish_text(%{state | partial: text}, join(state.committed, text)) do
        {:ok, state |> commit_watchdog() |> flush_candidate()}
      end
    end
  end

  defp recognition(state, :segment, text) do
    if String.trim(text) == "" do
      {:ok, state}
    else
      cumulative = join(state.committed, text)

      with {:ok, state} <-
             publish_text(
               %{
                 (state
                  |> cancel_candidate()
                  |> cancel_flush())
                 | committed: cumulative,
                   partial: ""
               },
               cumulative
             ) do
        {:ok, candidate(cancel_commit_watchdog(state))}
      end
    end
  end

  defp publish_text(state, text) when byte_size(text) <= @maximum_text_bytes do
    with {:ok, state} <- ensure_turn(state),
         :ok <- changed_text(state, text) do
      {:ok, %{state | last_text: text}}
    end
  end

  defp publish_text(_state, _text), do: {:error, :text_overflow}

  defp ensure_turn(%{turn: nil} = state) do
    turn = make_ref()

    case Event.emit(state.channel, :speech_started,
           turn_ref: turn,
           provider_request_id: state.request_id
         ) do
      result when result in [:ok, :discarded] -> {:ok, %{state | turn: turn}}
      _failure -> {:error, :session_failed}
    end
  end

  defp ensure_turn(state), do: {:ok, state}
  defp changed_text(%{last_text: text}, text), do: :ok

  defp changed_text(state, text) do
    case Event.emit(state.channel, :transcript,
           turn_ref: state.turn,
           text: text,
           provider_request_id: state.request_id
         ) do
      result when result in [:ok, :discarded] -> :ok
      _failure -> {:error, :session_failed}
    end
  end

  defp candidate(state) do
    token = make_ref()
    timer = Process.send_after(self(), {:inferred_endpoint, token}, state.gap)
    %{state | candidate: {timer, token}}
  end

  defp flush_candidate(%{committed: ""} = state), do: state

  defp flush_candidate(%{flush: nil} = state) do
    token = make_ref()
    timer = Process.send_after(self(), {:flush_draft, token}, state.gap)
    %{state | flush: {:gap, timer, token}}
  end

  defp flush_candidate(state), do: state

  defp cancel_flush_candidate(%{flush: {:gap, _timer, _token}} = state), do: cancel_flush(state)
  defp cancel_flush_candidate(state), do: state
  defp cancel_flush(%{flush: nil} = state), do: state

  defp cancel_flush(%{flush: {_phase, timer, _token}} = state) do
    Process.cancel_timer(timer)
    %{state | flush: nil}
  end

  defp request_commit(state) do
    state.wire_module.commit(state.wire)
  rescue
    _failure -> {:error, :session_failed}
  catch
    _kind, _reason -> {:error, :session_failed}
  end

  defp commit_watchdog(%{commit_watchdog: nil} = state) do
    token = make_ref()
    timer = Process.send_after(self(), {:commit_deadline, token}, state.commit_timeout)
    %{state | commit_watchdog: {timer, token}}
  end

  defp commit_watchdog(state), do: state
  defp cancel_commit_watchdog(%{commit_watchdog: nil} = state), do: state

  defp cancel_commit_watchdog(%{commit_watchdog: {timer, _token}} = state) do
    Process.cancel_timer(timer)
    %{state | commit_watchdog: nil}
  end

  defp cancel_candidate(%{candidate: nil} = state), do: state

  defp cancel_candidate(%{candidate: {timer, _token}} = state) do
    Process.cancel_timer(timer)
    %{state | candidate: nil}
  end

  defp join("", right), do: right
  defp join(left, ""), do: left
  defp join(left, right), do: String.trim_trailing(left) <> " " <> String.trim_leading(right)

  defp forward(_state, ""), do: :ok

  defp forward(state, audio) do
    bytes = min(byte_size(audio), 32_000)
    <<chunk::binary-size(bytes), rest::binary>> = audio
    with :ok <- state.wire_module.send_audio(state.wire, chunk), do: forward(state, rest)
  end

  defp fail(state), do: {:stop, {:shutdown, :session_failed}, state}
end
