defmodule Vxpipe.CallEngine.Provider.MorseCodeTTS.Session do
  @moduledoc "Native incremental Morse synthesis with bounded PCM credit; not human speech."
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.TTSProvider

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, TTSProvider}

  @impl true
  def configure(options) do
    allowed = Map.keys(Config.__struct__()) -- [:__struct__]

    with true <- is_list(options) and Keyword.keyword?(options),
         true <- length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))),
         true <- Enum.all?(Keyword.keys(options), &(&1 in allowed)),
         {:ok, config} <- Config.new(options) do
      Descriptor.new(
        kind: :tts,
        settings: config,
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: config.sample_rate,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :morse_code,
          model: :morse_code,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: :none,
        cache_identity: :crypto.hash(:sha256, :erlang.term_to_binary({:morse_tts, 1, config}))
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
  def close(pid), do: GenServer.stop(pid, :normal, 5_000)

  @impl true
  def init(options) do
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    private = Keyword.fetch!(options, :private)

    with {:ok, samples, interval} <- pacing(descriptor.settings, private),
         :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: :initialized) do
      {:ok,
       %{
         config: descriptor.settings,
         channel: channel,
         samples: samples,
         interval: interval,
         encoder: nil,
         request: nil,
         awaiting: nil,
         terminal?: false
       }}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:speak, reference, text}, _from, %{encoder: nil} = state) do
    with {:ok, encoder} <- Encoder.start(state.config, text),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :locally_measured
           ) do
      send(self(), {:emit, reference})
      {:reply, :ok, %{state | encoder: encoder, request: reference, terminal?: false}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:speak, _reference, _text}, _from, state), do: {:reply, {:error, :busy}, state}

  def handle_call({:cancel, reference, _playback}, _from, %{request: reference} = state) do
    result =
      if state.terminal?,
        do: :ok,
        else: Event.emit(state.channel, :cancelled, request_ref: reference)

    {:reply, result, %{state | encoder: nil, awaiting: nil, terminal?: true}}
  end

  def handle_call({:cancel, _reference, _playback}, _from, state),
    do: {:reply, {:error, :stale_request}, state}

  @impl true
  def handle_info(
        {:emit, reference},
        %{request: reference, encoder: encoder, awaiting: nil} = state
      )
      when not is_nil(encoder) do
    case Encoder.next(encoder, state.samples) do
      {:ok, audio, encoder} ->
        case Channel.submit(state.channel, reference, audio) do
          {:ok, credit} -> {:noreply, %{state | encoder: encoder, awaiting: credit}}
          {:error, :stale_request} -> {:noreply, %{state | encoder: nil}}
          _failure -> {:stop, :normal, state}
        end

      :done ->
        case Event.emit(state.channel, :completed, request_ref: reference) do
          :ok -> {:noreply, %{state | encoder: nil, terminal?: true}}
          {:error, :cancelled} -> {:noreply, %{state | encoder: nil}}
          _failure -> {:stop, :normal, state}
        end
    end
  end

  def handle_info(
        {:vxpipe_speech_credit, channel, reference, credit, :ok},
        %{channel: channel, request: reference, awaiting: credit} = state
      )
      when not is_nil(credit) do
    Process.send_after(self(), {:emit, reference}, state.interval)
    {:noreply, %{state | awaiting: nil}}
  end

  def handle_info(_stale, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :morse_tts_session)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp pacing(config, options) do
    chunk = Keyword.get(options, :chunk_duration_ms, 20)
    interval = Keyword.get(options, :emit_interval_ms, chunk)

    if is_integer(chunk) and chunk in 1..100 and rem(config.sample_rate * chunk, 1_000) == 0 and
         is_integer(interval) and interval in 0..1_000,
       do: {:ok, div(config.sample_rate * chunk, 1_000), interval},
       else: {:error, :invalid_configuration}
  end
end
