defmodule Vxpipe.CallEngine.Provider.Deepgram.Flux.Session do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxSocket}
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event}

  @derive {Inspect, only: [:last_sequence]}
  defstruct [
    :channel,
    :wire,
    :wire_module,
    last_sequence: -1,
    turns: %{}
  ]

  @impl true
  def configure(options) do
    with {:ok, options} <- Keyword.validate(options, [:model, :encoding, :sample_rate]),
         :ok <- Flux.validate_options(options) do
      model = Keyword.get(options, :model, "flux-general-en")
      encoding = Keyword.fetch!(options, :encoding)
      sample_rate = Keyword.fetch!(options, :sample_rate)

      Descriptor.new(
        kind: :stt,
        settings: %{model: model, encoding: encoding, sample_rate: sample_rate},
        format: provider_format(%{codec: encoding, sample_rate: sample_rate}),
        usage_identity: %{
          provider: :deepgram,
          model: model,
          provenance: :provider_reported
        },
        readiness: :provider_acknowledged,
        endpointing: :provider_semantic,
        speech_start?: true,
        eager_end?: true,
        resume?: true
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def start_link(options),
    do: Vxpipe.CallEngine.Speech.STTProvider.start_link(__MODULE__, options)

  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:push_audio, audio}, 5_000)

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
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    wire_module = Keyword.get(private, :wire_module, FluxSocket)
    wire_options = Keyword.get(private, :wire_options, [])

    with %Flux{} <- config,
         true <- matching_configuration?(descriptor, config),
         true <- valid_wire?(wire_module, wire_options),
         :ok <- Channel.bind(channel),
         {:ok, wire} <-
           wire_module.start_link(
             owner: self(),
             connection: Flux.connection_options(config),
             transport_options: wire_options
           ) do
      {:ok,
       %__MODULE__{
         channel: channel,
         wire: wire,
         wire_module: wire_module
       }}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:push_audio, audio}, _from, state) do
    case state.wire_module.send_audio(state.wire, audio) do
      :ok -> {:reply, :ok, state}
      {:error, _reason} -> fail_call(state)
    end
  catch
    :exit, _reason -> fail_call(state)
  end

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
        {:vxpipe_stt_transport, wire, {:message, payload}},
        %{wire: wire} = state
      ) do
    case Flux.decode(payload) do
      {:ok, %Signal{provider_sequence: sequence}} when sequence <= state.last_sequence ->
        {:noreply, state}

      {:ok, %Signal{} = signal} ->
        case publish(signal, state) do
          {:ok, state} -> {:noreply, %{state | last_sequence: signal.provider_sequence}}
          {:error, _reason} -> stop_session(state)
        end

      {:ignore, _reason} ->
        {:noreply, state}

      {:error, _reason} ->
        stop_session(state)
    end
  end

  def handle_info(
        {:vxpipe_stt_transport, wire, {:closed, _reason}},
        %{wire: wire} = state
      ),
      do: stop_session(state)

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :deepgram_flux_stt)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp publish(%Signal{kind: :connected} = signal, state) do
    emit(state, :ready,
      readiness: :provider_acknowledged,
      provider_request_id: signal.request_id
    )
  end

  defp publish(%Signal{kind: :turn_started} = signal, state) do
    turn_ref = make_ref()

    case Event.emit(state.channel, :speech_started,
           turn_ref: turn_ref,
           provider_request_id: signal.request_id
         ) do
      :ok ->
        state = %{state | turns: Map.put(state.turns, signal.provider_turn_index, turn_ref)}
        emit_initial_transcript(state, signal, turn_ref)

      :discarded ->
        {:ok, state}

      {:error, _reason} = error ->
        error
    end
  end

  defp publish(%Signal{kind: :transcript_updated} = signal, state),
    do: emit_turn(state, signal, :transcript, [])

  defp publish(%Signal{kind: :eager_turn_ended} = signal, state),
    do: emit_turn(state, signal, :eager_turn_ended, endpointing: :provider_semantic)

  defp publish(%Signal{kind: :turn_resumed} = signal, state),
    do: emit_turn(state, signal, :turn_resumed, [])

  defp publish(%Signal{kind: :turn_ended} = signal, state) do
    with {:ok, state} <-
           emit_turn(state, signal, :turn_ended, endpointing: :provider_semantic) do
      {:ok, %{state | turns: Map.delete(state.turns, signal.provider_turn_index)}}
    end
  end

  defp publish(%Signal{kind: :failed}, _state), do: {:error, :provider_failed}
  defp publish(%Signal{}, state), do: {:ok, state}

  defp emit(state, kind, fields) do
    case Event.emit(state.channel, kind, fields) do
      :ok -> {:ok, state}
      :discarded -> {:ok, state}
      {:error, _reason} = error -> error
    end
  end

  defp emit_turn(state, signal, kind, extra) do
    case Map.fetch(state.turns, signal.provider_turn_index) do
      {:ok, turn_ref} ->
        fields = turn_fields(kind, turn_ref, signal) ++ extra

        emit(state, kind, fields)

      :error ->
        {:ok, state}
    end
  end

  defp turn_fields(:turn_resumed, turn_ref, signal),
    do: [turn_ref: turn_ref, provider_request_id: signal.request_id]

  defp turn_fields(kind, turn_ref, signal) when kind in [:turn_ended, :eager_turn_ended] do
    [
      turn_ref: turn_ref,
      text: signal.text || "",
      provider_request_id: signal.request_id,
      audio_duration_ms: signal.audio_duration_ms
    ]
  end

  defp turn_fields(_kind, turn_ref, signal),
    do: [
      turn_ref: turn_ref,
      text: signal.text || "",
      provider_request_id: signal.request_id
    ]

  defp emit_initial_transcript(state, %{text: text}, _turn_ref) when text in [nil, ""],
    do: {:ok, state}

  defp emit_initial_transcript(state, signal, turn_ref) do
    emit(state, :transcript,
      turn_ref: turn_ref,
      text: signal.text,
      provider_request_id: signal.request_id
    )
  end

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
    } and
      descriptor.format == provider_format(Flux.media_format(config))
  end

  defp valid_wire?(module, options) do
    is_atom(module) and is_list(options) and Keyword.keyword?(options) and
      Code.ensure_loaded?(module) and function_exported?(module, :start_link, 1) and
      function_exported?(module, :send_audio, 2) and function_exported?(module, :close, 1)
  end

  defp provider_format(%{codec: :linear16, sample_rate: sample_rate}) do
    %{
      encoding: :linear16,
      container: :raw,
      sample_rate: sample_rate,
      channels: 1,
      byte_order: :little,
      signed?: true
    }
  end

  defp provider_format(%{codec: :opus, sample_rate: sample_rate}) do
    %{encoding: :opus, container: :raw, sample_rate: sample_rate, channels: 1}
  end
end
