defmodule Vxpipe.Providers.Rime.TTSSession do
  @moduledoc false

  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.TTSProvider

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, Playback, TTSProvider}
  alias Vxpipe.Providers.Rime.{TTS, TTSSocket}

  @request_timeout 60_000

  @derive {Inspect, only: [:request, :cancelling?, :pending_done?]}
  defstruct [
    :channel,
    :request,
    :last_terminal_request,
    :request_timer,
    :awaiting,
    :wire,
    :wire_module,
    cancelling?: false,
    pending_done?: false
  ]

  @impl true
  defdelegate models(), to: Vxpipe.Providers.Rime.TTS

  @impl true
  def configure(options) do
    with {:ok, public} <- TTS.public_options(options) do
      Descriptor.new(
        kind: :tts,
        settings: public,
        format: %{
          encoding: :linear16,
          container: :raw,
          channels: 1,
          byte_order: :little,
          signed?: true,
          sample_rate: public.sample_rate
        },
        usage_identity: %{provider: :rime, model: :coda, provenance: :provider_reported},
        readiness: :initialized,
        endpointing: :none,
        cache_identity: :crypto.hash(:sha256, :erlang.term_to_binary({:rime_coda_tts, 1, public}))
      )
    end
  end

  @impl true
  def start_link(options), do: TTSProvider.start_link(__MODULE__, options)

  @impl true
  def speak(pid, reference, text), do: GenServer.call(pid, {:speak, reference, text}, 5_000)

  @impl true
  def cancel(pid, reference, playback),
    do: GenServer.call(pid, {:cancel, reference, playback}, 5_000)

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
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    wire_module = Keyword.get(private, :wire_module, TTSSocket)
    wire_options = Keyword.get(private, :wire_options, [])

    with %TTS{} <- config,
         {:ok, expected} <- configure(config_options(config)),
         true <- descriptor == expected,
         true <- is_atom(wire_module) and is_list(wire_options),
         :ok <- Channel.bind(channel),
         {:ok, wire} <-
           wire_module.start_link(
             owner: self(),
             connection: TTS.connection_options(config),
             transport_options: wire_options
           ),
         :ok <- Event.emit(channel, :ready, readiness: :initialized) do
      {:ok, %__MODULE__{channel: channel, wire: wire, wire_module: wire_module}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:speak, reference, text}, _from, %{request: nil} = state) do
    with {:ok, payload} <- TTS.encode_text(text),
         :ok <- state.wire_module.send_control(state.wire, payload),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :provider_reported
           ),
         :ok <- state.wire_module.send_control(state.wire, TTS.encode_flush()) do
      timer = Process.send_after(self(), {:request_timeout, reference}, @request_timeout)

      {:reply, :ok,
       %{state | request: reference, request_timer: timer, last_terminal_request: nil}}
    else
      {:error, :invalid_text} -> {:reply, {:error, :invalid_text}, state}
      _failure -> fail_call(state)
    end
  end

  def handle_call({:speak, _reference, _text}, _from, state),
    do: {:reply, {:error, :busy}, state}

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: nil, last_terminal_request: reference} = state
      ),
      do: {:reply, :ok, state}

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: reference} = state
      ) do
    state = release_awaiting(state)
    state = %{state | cancelling?: true}

    case maybe_finish(state) do
      {:ok, state} -> {:reply, :ok, state}
      _failure -> fail_call(state)
    end
  end

  def handle_call({:cancel, _reference, _playback}, _from, state),
    do: {:reply, {:error, :stale_request}, state}

  def handle_call(:close, _from, state) do
    _ = state.wire_module.close(state.wire)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:vxpipe_tts_transport, wire, {:audio, wire_ref, audio}}, %{wire: wire} = state) do
    cond do
      state.request == nil or state.cancelling? ->
        acknowledge_wire(state, wire_ref)
        {:noreply, state}

      state.awaiting != nil ->
        {:stop, :normal, state}

      true ->
        case TTS.validate_audio(audio) do
          {:audio, audio} ->
            case Channel.submit(state.channel, state.request, audio) do
              {:ok, credit} -> {:noreply, %{state | awaiting: {credit, wire_ref}}}
              _failure -> {:stop, :normal, state}
            end

          _invalid ->
            {:stop, :normal, state}
        end
    end
  end

  def handle_info({:vxpipe_tts_transport, wire, {:control, signal}}, %{wire: wire} = state) do
    case decode_signal(signal) do
      :done when state.request != nil ->
        state = %{state | pending_done?: true}

        case maybe_finish(state) do
          {:ok, state} -> {:noreply, state}
          _failure -> {:stop, :normal, state}
        end

      :ignore ->
        {:noreply, state}

      _invalid ->
        {:stop, :normal, state}
    end
  end

  def handle_info({:vxpipe_tts_transport, wire, {:closed, _reason}}, %{wire: wire} = state),
    do: {:stop, :normal, state}

  def handle_info({:request_timeout, request}, %{request: request} = state),
    do: {:stop, :normal, state}

  def handle_info({:request_timeout, _old_request}, state), do: {:noreply, state}

  def handle_info(
        {:vxpipe_speech_credit, channel, request, credit, :ok},
        %{channel: channel, request: request, awaiting: {credit, wire_ref}} = state
      ) do
    acknowledge_wire(state, wire_ref)
    state = %{state | awaiting: nil}

    case maybe_finish(state) do
      {:ok, state} -> {:noreply, state}
      _failure -> {:stop, :normal, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :rime_coda_tts)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp maybe_finish(%{pending_done?: true, awaiting: nil, request: request} = state) do
    kind = if state.cancelling?, do: :cancelled, else: :completed

    with :ok <- Event.emit(state.channel, kind, request_ref: request) do
      Process.cancel_timer(state.request_timer)

      {:ok,
       %{
         state
         | request: nil,
           request_timer: nil,
           last_terminal_request: request,
           cancelling?: false,
           pending_done?: false
       }}
    end
  end

  defp maybe_finish(state), do: {:ok, state}

  defp release_awaiting(%{awaiting: {_credit, wire_ref}} = state) do
    acknowledge_wire(state, wire_ref)
    %{state | awaiting: nil}
  end

  defp release_awaiting(state), do: state

  defp acknowledge_wire(state, reference) do
    send(state.wire, {:vxpipe_tts_audio_result, self(), reference, :ok})
  end

  defp decode_signal(signal) when is_binary(signal), do: TTS.decode(signal)
  defp decode_signal(signal), do: signal

  defp config_options(config),
    do: [model: config.model, speaker: config.speaker, sample_rate: config.sample_rate]

  defp fail_call(state), do: {:stop, :normal, {:error, :provider_unavailable}, state}
end
