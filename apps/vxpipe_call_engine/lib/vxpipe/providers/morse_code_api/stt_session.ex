defmodule Vxpipe.Providers.MorseCodeApi.STTSession do
  @moduledoc """
  Scoped recognition for the fixed Morse API profile. The acknowledged server
  commits after 840 ms of PCM silence, beyond its 420 ms word gap. Only those
  commits end turns; transcript inactivity never promotes a draft to a final.
  """
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, SessionTree, STTProvider}
  alias Vxpipe.Providers.MorseCodeApi.{STT, STTSocket}
  @maximum_audio_bytes 96_000
  @setup_timeout_ms 15_000
  @commit_timeout_ms 60_000

  @impl true
  defdelegate models(), to: STT

  @impl true
  def configure(options) do
    with {:ok, public} <- STT.public_options(options) do
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
          provider: :morse_code_api,
          model: public.model,
          provenance: :locally_measured
        },
        readiness: :provider_acknowledged,
        endpointing: :provider_gap,
        speech_start?: true,
        speech_start_evidence: :transcript
      )
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
    setup_timeout = Keyword.get(private, :setup_timeout_ms, @setup_timeout_ms)
    commit_timeout = Keyword.get(private, :commit_timeout_ms, @commit_timeout_ms)
    channel = Keyword.fetch!(options, :channel)

    with %STT{} <- config,
         {:ok, descriptor} <-
           configure(
             model: config.model,
             encoding: config.encoding,
             sample_rate: config.sample_rate
           ),
         true <- descriptor == Keyword.fetch!(options, :descriptor),
         true <- is_integer(setup_timeout) and setup_timeout in 1..@setup_timeout_ms,
         true <- is_integer(commit_timeout) and commit_timeout in 1..@commit_timeout_ms,
         :ok <- Channel.bind(channel) do
      {:ok,
       %{
         allocation: Keyword.fetch!(options, :allocation),
         channel: channel,
         config: config,
         wire_module: Keyword.get(private, :wire_module, STTSocket),
         wire_options: Keyword.get(private, :wire_options, []),
         wire: nil,
         monitor: nil,
         ready?: false,
         request_id: nil,
         setup_timeout: setup_timeout,
         setup_timer: nil,
         commit_timeout: commit_timeout,
         watchdog: nil,
         turn: nil,
         text: "",
         accepted_samples: 0,
         settled_samples: 0
       }, {:continue, :connect}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    options = [
      owner: self(),
      connection: STT.connection_options(state.config),
      transport_options: state.wire_options
    ]

    child = %{
      id: state.wire_module,
      start: {state.wire_module, :start_link, [options]},
      restart: :temporary,
      shutdown: :brutal_kill
    }

    case DynamicSupervisor.start_child(SessionTree.providers(state.allocation), child) do
      {:ok, wire} ->
        {:noreply,
         %{
           state
           | wire: wire,
             monitor: Process.monitor(wire),
             setup_timer: Process.send_after(self(), :setup_timeout, state.setup_timeout)
         }}

      _failure ->
        fail(state)
    end
  end

  @impl true
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

  def handle_call({:push_audio, _invalid}, _from, state),
    do: {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}

  @impl true
  def handle_info(
        {:vxpipe_scribe_transport, wire, {:event, {:ready, request_id}}},
        %{wire: wire, ready?: false} = state
      ) do
    case Event.emit(state.channel, :ready, readiness: :provider_acknowledged) do
      result when result in [:ok, :discarded] ->
        Process.cancel_timer(state.setup_timer)
        {:noreply, %{state | ready?: true, request_id: request_id, setup_timer: nil}}

      _failure ->
        fail(state)
    end
  end

  def handle_info(
        {:vxpipe_scribe_transport, wire, {:event, {kind, text}}},
        %{wire: wire, ready?: true} = state
      )
      when kind in [:partial, :segment] and is_binary(text) do
    case recognize(state, kind, String.trim(text)) do
      {:ok, updated} -> {:noreply, updated}
      _failure -> fail(state)
    end
  end

  def handle_info({:vxpipe_scribe_transport, wire, _invalid}, %{wire: wire} = state),
    do: fail(state)

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{monitor: monitor, wire: wire} = state
      ),
      do: fail(state)

  def handle_info(:setup_timeout, %{ready?: false} = state), do: fail(state)
  def handle_info({:commit_timeout, token}, %{watchdog: {_timer, token}} = state), do: fail(state)
  def handle_info(_stale, state), do: {:noreply, state}

  defp recognize(state, _kind, ""), do: {:ok, state}

  defp recognize(state, kind, text) do
    with {:ok, state} <- start_turn(state),
         {:ok, state} <- revise(state, text) do
      if kind == :segment do
        duration = div((state.accepted_samples - state.settled_samples) * 1_000, 16_000)

        with result when result in [:ok, :discarded] <-
               emit(state, :turn_ended,
                 turn_ref: state.turn,
                 text: text,
                 endpointing: :provider_gap,
                 audio_duration_ms: duration
               ) do
          {:ok,
           %{clear_watchdog(state) | turn: nil, text: "", settled_samples: state.accepted_samples}}
        end
      else
        {:ok, state}
      end
    end
  end

  defp start_turn(%{turn: nil} = state) do
    ref = make_ref()

    with result when result in [:ok, :discarded] <- emit(state, :speech_started, turn_ref: ref),
         do: {:ok, %{state | turn: ref}}
  end

  defp start_turn(state), do: {:ok, state}

  defp revise(%{text: text} = state, text), do: {:ok, state}

  defp revise(state, text) do
    with result when result in [:ok, :discarded] <-
           emit(state, :transcript, turn_ref: state.turn, text: text) do
      state = clear_watchdog(state)
      token = make_ref()
      timer = Process.send_after(self(), {:commit_timeout, token}, state.commit_timeout)
      {:ok, %{state | text: text, watchdog: {timer, token}}}
    end
  end

  defp clear_watchdog(state) do
    if state.watchdog, do: Process.cancel_timer(elem(state.watchdog, 0))
    %{state | watchdog: nil}
  end

  defp emit(state, kind, fields),
    do:
      Event.emit(state.channel, kind, Keyword.put(fields, :provider_request_id, state.request_id))

  defp forward(_state, ""), do: :ok

  defp forward(state, audio) do
    size = min(byte_size(audio), 32_000)
    <<chunk::binary-size(size), rest::binary>> = audio
    with :ok <- state.wire_module.send_audio(state.wire, chunk), do: forward(state, rest)
  catch
    :exit, _reason -> {:error, :connection_lost}
  end

  defp fail(state), do: {:stop, {:shutdown, :session_failed}, state}
end
