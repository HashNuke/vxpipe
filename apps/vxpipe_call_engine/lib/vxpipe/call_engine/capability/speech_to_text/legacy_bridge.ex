defmodule Vxpipe.CallEngine.Capability.SpeechToText.LegacyBridge do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Provider.Deepgram.Flux
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event}

  @derive {Inspect, only: [:last_sequence]}
  defstruct [
    :allocation,
    :channel,
    :provider,
    :transport,
    :transport_module,
    last_sequence: -1,
    turns: %{}
  ]

  def public_options(Flux, %Flux{} = config) do
    [
      format: provider_format(Flux.media_format(config)),
      model: config.model,
      readiness: :provider_acknowledged
    ]
  end

  def public_options(_provider, _config), do: nil

  @impl true
  def configure(options) do
    with {:ok, options} <- Keyword.validate(options, [:format, :model, :readiness]),
         format when is_map(format) <- Keyword.get(options, :format),
         model when is_binary(model) <- Keyword.get(options, :model),
         readiness when readiness in [:initialized, :provider_acknowledged] <-
           Keyword.get(options, :readiness) do
      Descriptor.new(
        kind: :stt,
        settings: %{model: model},
        format: format,
        usage_identity: %{
          provider: :deepgram,
          model: model,
          provenance: :provider_reported
        },
        readiness: readiness,
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
    channel = Keyword.fetch!(options, :channel)
    allocation = Keyword.fetch!(options, :allocation)
    private = Keyword.fetch!(options, :private)
    provider = Keyword.fetch!(private, :provider)
    config = Keyword.fetch!(private, :config)
    {transport_module, transport_options} = Keyword.fetch!(private, :transport)
    connection = provider.connection_options(config)

    with :ok <- Channel.bind(channel),
         {:ok, transport} <-
           transport_module.start_link(
             owner: self(),
             connection: connection,
             transport_options: transport_options
           ) do
      {:ok,
       %__MODULE__{
         allocation: allocation,
         channel: channel,
         provider: provider,
         transport: transport,
         transport_module: transport_module
       }}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:push_audio, audio}, _from, state) do
    case state.transport_module.send_audio(state.transport, audio) do
      :ok -> {:reply, :ok, state}
      {:error, _reason} -> fail_bridge_call(state)
    end
  catch
    :exit, _reason -> fail_bridge_call(state)
  end

  def handle_call(:close, _from, state) do
    case state.transport_module.close(state.transport) do
      :ok -> {:stop, :normal, :ok, state}
      _error -> fail_bridge_call(state)
    end
  catch
    :exit, _reason -> fail_bridge_call(state)
  end

  @impl true
  def handle_info(
        {:vxpipe_stt_transport, transport, {:message, payload}},
        %{transport: transport} = state
      ) do
    case state.provider.decode(payload) do
      {:ok, %Signal{provider_sequence: sequence}} when sequence <= state.last_sequence ->
        {:noreply, state}

      {:ok, %Signal{} = signal} ->
        case publish(signal, state) do
          {:ok, state} -> {:noreply, %{state | last_sequence: signal.provider_sequence}}
          {:error, _reason} -> stop_bridge(state)
        end

      {:ignore, _reason} ->
        {:noreply, state}

      {:error, _reason} ->
        stop_bridge(state)
    end
  end

  def handle_info(
        {:vxpipe_stt_transport, transport, {:closed, _reason}},
        %{transport: transport} = state
      ),
      do: stop_bridge(state)

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :legacy_stt_bridge)
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

  defp stop_bridge(state) do
    notify_failure(state.allocation)
    _ = state.transport_module.close(state.transport)
    {:stop, {:shutdown, :session_failed}, state}
  catch
    :exit, _reason -> {:stop, {:shutdown, :session_failed}, state}
  end

  defp fail_bridge_call(state) do
    notify_failure(state.allocation)
    {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
  end

  defp notify_failure(%{lease: lease} = allocation) when is_pid(lease) do
    send(lease, {:legacy_stt_bridge_failed, allocation})
    :ok
  end

  defp notify_failure(_allocation), do: :ok

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
