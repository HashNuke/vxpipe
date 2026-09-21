defmodule Vxpipe.Providers.Deepgram.TTSSession do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.TTSProvider

  alias Vxpipe.Providers.Deepgram.{FluxTextToSpeech, TTSSocket}
  alias Vxpipe.Providers.Deepgram.FluxTextToSpeech.Signal
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, Playback, TTSProvider}

  @derive {Inspect, only: [:phase, :ready?, :terminal?]}
  defstruct [
    :awaiting,
    :channel,
    :phase,
    :request,
    :last_terminal_request,
    :pending_terminal,
    :speech_id,
    :wire,
    :wire_module,
    ready?: false,
    terminal?: false
  ]

  @impl true
  def configure(options) do
    with {:ok, options} <- Keyword.validate(options, [:model, :encoding, :sample_rate]),
         :ok <- FluxTextToSpeech.validate_options(options) do
      settings = %{
        model: Keyword.get(options, :model, "flux-haley-en"),
        encoding: Keyword.get(options, :encoding, :linear16),
        sample_rate: Keyword.get(options, :sample_rate, 48_000)
      }

      Descriptor.new(
        kind: :tts,
        settings: settings,
        format: provider_format(settings),
        usage_identity: %{
          provider: :deepgram,
          model: settings.model,
          provenance: :provider_reported
        },
        readiness: :provider_acknowledged,
        endpointing: :none,
        cache_identity:
          :crypto.hash(
            :sha256,
            :erlang.term_to_binary({:deepgram_flux_tts, 1, settings})
          )
      )
    else
      _invalid -> {:error, :invalid_configuration}
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

    with %FluxTextToSpeech{} <- config,
         true <- matching_configuration?(descriptor, config),
         true <- valid_wire?(wire_module, wire_options),
         :ok <- Channel.bind(channel),
         {:ok, wire} <-
           wire_module.start_link(
             owner: self(),
             connection: FluxTextToSpeech.connection_options(config),
             transport_options: wire_options
           ) do
      {:ok,
       %__MODULE__{
         channel: channel,
         phase: :idle,
         wire: wire,
         wire_module: wire_module
       }}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:speak, reference, text}, _from, %{request: nil} = state) do
    with :ok <- send_control(state, FluxTextToSpeech.encode_speak(text)),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :provider_reported
           ) do
      case send_control(state, FluxTextToSpeech.encode_flush()) do
        :ok -> {:reply, :ok, activate_request(state, reference)}
        _failure -> fail_call(state)
      end
    else
      _failure -> fail_call(state)
    end
  catch
    :exit, _reason -> fail_call(state)
  end

  def handle_call({:speak, _reference, _text}, _from, state),
    do: {:reply, {:error, :busy}, state}

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: reference, terminal?: true} = state
      ) do
    {:reply, :ok, reset_request(state)}
  end

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: nil, last_terminal_request: reference} = state
      ) do
    {:reply, :ok, %{state | last_terminal_request: nil}}
  end

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: reference, pending_terminal: {:terminal, provider_id}} = state
      ) do
    state = release_awaiting(state)

    case Event.emit(state.channel, :cancelled,
           request_ref: reference,
           provider_request_id: provider_id
         ) do
      :ok -> {:reply, :ok, reset_request(state)}
      _failure -> fail_call(state)
    end
  end

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference} = playback},
        _from,
        %{request: reference, terminal?: false} = state
      ) do
    state = release_awaiting(state)

    if playback.request_played_ms > 0 do
      case send_control(state, FluxTextToSpeech.encode_interrupt(playback.session_played_ms)) do
        :ok -> {:reply, :ok, %{state | pending_terminal: nil, phase: :interrupting}}
        _failure -> fail_call(state)
      end
    else
      {:reply, :ok, %{state | pending_terminal: nil, phase: :discarding}}
    end
  catch
    :exit, _reason -> fail_call(state)
  end

  def handle_call({:cancel, _reference, _playback}, _from, state),
    do: {:reply, {:error, :stale_request}, state}

  def handle_call(:close, _from, state) do
    case state.wire_module.close(state.wire) do
      :ok -> {:stop, :normal, :ok, state}
      _error -> fail_call(state)
    end
  catch
    :exit, _reason -> fail_call(state)
  end

  @impl true
  def handle_info(
        {:vxpipe_tts_transport, wire, {:control, payload}},
        %{wire: wire} = state
      ) do
    case FluxTextToSpeech.decode(payload) do
      {:ok, %Signal{} = signal} ->
        case publish(signal, state) do
          {:ok, state} -> {:noreply, state}
          {:error, _reason} -> stop_session(state)
        end

      {:ignore, _reason} ->
        {:noreply, state}

      {:error, _reason} ->
        stop_session(state)
    end
  end

  def handle_info(
        {:vxpipe_tts_transport, wire, {:audio, wire_reference, payload}},
        %{wire: wire} = state
      )
      when is_reference(wire_reference) do
    handle_audio(wire_reference, payload, state)
  end

  def handle_info(
        {:vxpipe_tts_transport, wire, {:closed, _reason}},
        %{wire: wire} = state
      ),
      do: stop_session(state)

  def handle_info(
        {:vxpipe_speech_credit, channel, request, credit, :ok},
        %{
          channel: channel,
          request: request,
          awaiting: %{channel: credit, wire: wire_reference}
        } = state
      ) do
    acknowledge_wire(state, wire_reference, :ok)
    state = %{state | awaiting: nil}

    case state.pending_terminal do
      nil ->
        {:noreply, state}

      {:terminal, provider_id} ->
        case terminal(%{state | pending_terminal: nil}, provider_id) do
          {:ok, state} -> {:noreply, state}
          {:error, _reason} -> stop_session(state)
        end
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :deepgram_flux_tts)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp handle_audio(wire_reference, payload, %{phase: phase} = state)
       when phase in [:active, :streaming] do
    case {state.awaiting, FluxTextToSpeech.decode_audio(payload)} do
      {nil, {:audio, audio}} -> submit_audio(wire_reference, audio, state)
      _failure -> reject_audio(wire_reference, state)
    end
  end

  defp handle_audio(wire_reference, payload, %{phase: phase} = state)
       when phase in [:fenced, :discarding, :interrupting] do
    case FluxTextToSpeech.decode_audio(payload) do
      {:audio, _audio} ->
        acknowledge_wire(state, wire_reference, :ok)
        {:noreply, state}

      {:error, _reason} ->
        reject_audio(wire_reference, state)
    end
  end

  defp handle_audio(wire_reference, _payload, state), do: reject_audio(wire_reference, state)

  defp submit_audio(wire_reference, audio, state) do
    case Channel.submit(state.channel, state.request, audio) do
      {:ok, credit} ->
        {:noreply,
         %{
           state
           | awaiting: %{channel: credit, wire: wire_reference},
             phase: :streaming
         }}

      {:error, :stale_request} ->
        acknowledge_wire(state, wire_reference, :ok)
        {:noreply, %{state | phase: :fenced}}

      _failure ->
        reject_audio(wire_reference, state)
    end
  end

  defp reject_audio(wire_reference, state) do
    acknowledge_wire(state, wire_reference, {:error, :audio_output_failed})
    stop_session(state)
  end

  defp publish(%Signal{kind: :connected, request_id: request_id}, %{ready?: false} = state) do
    case Event.emit(state.channel, :ready,
           readiness: :provider_acknowledged,
           provider_request_id: request_id
         ) do
      :ok -> {:ok, %{state | ready?: true}}
      _failure -> {:error, :session_failed}
    end
  end

  defp publish(%Signal{kind: :connected}, %{ready?: true} = state), do: {:ok, state}

  defp publish(%Signal{kind: kind} = signal, state)
       when kind in [:speech_started, :flushed] do
    associate_speech(state, signal.provider_speech_id)
  end

  defp publish(%Signal{kind: :speech_completed} = signal, state) do
    with {:ok, state} <- associate_speech(state, signal.provider_speech_id) do
      if state.awaiting,
        do: {:ok, %{state | pending_terminal: {:terminal, signal.provider_speech_id}}},
        else: terminal(state, signal.provider_speech_id)
    end
  end

  defp publish(%Signal{kind: :speech_interrupted} = signal, %{phase: phase} = state)
       when phase in [:discarding, :interrupting] do
    with {:ok, state} <- associate_speech(state, signal.provider_speech_id) do
      cancelled(state, signal.provider_speech_id)
    end
  end

  defp publish(%Signal{kind: :speech_interrupted}, _state),
    do: {:error, :invalid_provider_state}

  defp publish(%Signal{kind: :warning}, state), do: {:ok, state}
  defp publish(%Signal{kind: :failed}, _state), do: {:error, :provider_failed}

  defp terminal(%{phase: phase} = state, provider_id)
       when phase in [:active, :streaming] do
    case Event.emit(state.channel, :completed,
           request_ref: state.request,
           provider_request_id: provider_id
         ) do
      :ok ->
        reference = state.request
        {:ok, %{reset_request(state) | last_terminal_request: reference}}

      {:error, :cancelled} ->
        fenced_terminal(state, provider_id)

      _failure ->
        {:error, :session_failed}
    end
  end

  defp terminal(%{phase: phase} = state, provider_id)
       when phase in [:discarding, :interrupting],
       do: cancelled(state, provider_id)

  defp terminal(%{phase: :fenced} = state, provider_id),
    do: fenced_terminal(state, provider_id)

  defp terminal(%{request: nil} = state, _provider_id), do: {:ok, state}
  defp terminal(_state, _provider_id), do: {:error, :invalid_provider_state}

  defp cancelled(state, provider_id) do
    case Event.emit(state.channel, :cancelled,
           request_ref: state.request,
           provider_request_id: provider_id
         ) do
      :ok -> {:ok, reset_request(state)}
      _failure -> {:error, :session_failed}
    end
  end

  defp fenced_terminal(state, provider_id) do
    state = release_awaiting(state)

    case Event.emit(state.channel, :cancelled,
           request_ref: state.request,
           provider_request_id: provider_id
         ) do
      :ok -> {:ok, %{state | phase: :completed, terminal?: true}}
      _failure -> {:error, :session_failed}
    end
  end

  defp associate_speech(%{request: nil} = state, _provider_id), do: {:ok, state}
  defp associate_speech(state, nil), do: {:ok, state}

  defp associate_speech(%{speech_id: nil} = state, provider_id),
    do: {:ok, %{state | speech_id: provider_id}}

  defp associate_speech(%{speech_id: provider_id} = state, provider_id), do: {:ok, state}
  defp associate_speech(_state, _provider_id), do: {:error, :invalid_provider_state}

  defp reset_request(state) do
    %{
      state
      | awaiting: nil,
        pending_terminal: nil,
        phase: :idle,
        request: nil,
        speech_id: nil,
        terminal?: false
    }
  end

  defp activate_request(state, reference) do
    %{
      state
      | awaiting: nil,
        last_terminal_request: nil,
        pending_terminal: nil,
        phase: :active,
        request: reference,
        speech_id: nil,
        terminal?: false
    }
  end

  defp release_awaiting(%{awaiting: nil} = state), do: state

  defp release_awaiting(%{awaiting: %{wire: wire_reference}} = state) do
    acknowledge_wire(state, wire_reference, :ok)
    %{state | awaiting: nil}
  end

  defp acknowledge_wire(state, reference, result) do
    send(state.wire, {:vxpipe_tts_audio_result, self(), reference, result})
    :ok
  end

  defp send_control(state, payload),
    do: state.wire_module.send_control(state.wire, payload)

  defp stop_session(state) do
    _ = state.wire_module.close(state.wire)
    {:stop, {:shutdown, :session_failed}, state}
  catch
    :exit, _reason -> {:stop, {:shutdown, :session_failed}, state}
  end

  defp fail_call(state) do
    {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
  end

  defp matching_configuration?(descriptor, config) do
    descriptor.settings == %{
      model: config.model,
      encoding: config.encoding,
      sample_rate: config.sample_rate
    } and descriptor.format == provider_format(descriptor.settings)
  end

  defp valid_wire?(module, options) do
    is_atom(module) and is_list(options) and Keyword.keyword?(options) and
      Code.ensure_loaded?(module) and function_exported?(module, :start_link, 1) and
      function_exported?(module, :send_control, 2) and function_exported?(module, :close, 1)
  end

  defp provider_format(%{sample_rate: sample_rate}) do
    %{
      encoding: :linear16,
      container: :raw,
      sample_rate: sample_rate,
      channels: 1,
      byte_order: :little,
      signed?: true
    }
  end
end
