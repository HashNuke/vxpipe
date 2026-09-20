defmodule Vxpipe.CallEngine.SpeechGuideTTSProvider do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.TTSProvider

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, Playback, TTSProvider}

  @impl true
  def configure(options) do
    with {:ok, options} <- Keyword.validate(options, sample_rate: 16_000),
         sample_rate when is_integer(sample_rate) and sample_rate > 0 <-
           Keyword.fetch!(options, :sample_rate) do
      Descriptor.new(
        kind: :tts,
        settings: %{sample_rate: sample_rate},
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: sample_rate,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :guide,
          model: :minimal,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: :none,
        cache_identity: :crypto.hash(:sha256, :erlang.term_to_binary({__MODULE__, sample_rate}))
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def start_link(options), do: TTSProvider.start_link(__MODULE__, options)

  @impl true
  def speak(pid, reference, text),
    do: GenServer.call(pid, {:speak, reference, text}, 5_000)

  @impl true
  def cancel(pid, reference, playback),
    do: GenServer.call(pid, {:cancel, reference, playback}, 5_000)

  @impl true
  def close(pid), do: GenServer.call(pid, :close, 5_000)

  @impl true
  def init(options) do
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    private = Keyword.fetch!(options, :private)
    credential = Keyword.get(private, :credential)
    observer = Keyword.get(private, :observer)

    with true <- is_binary(credential) and byte_size(credential) > 0,
         true <- is_pid(observer),
         :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: :initialized) do
      send(observer, {:speech_guide_client_initialized, self()})

      {:ok,
       %{
         awaiting: nil,
         channel: channel,
         last_terminal_request: nil,
         request: nil
       }}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:speak, reference, _text}, _from, %{request: nil} = state) do
    audio = <<0, 0>>

    with :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :locally_measured
           ),
         {:ok, credit} <- Channel.submit(state.channel, reference, audio) do
      {:reply, :ok, %{state | request: reference, awaiting: credit}}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:speak, _reference, _text}, _from, state),
    do: {:reply, {:error, :busy}, state}

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: reference} = state
      ) do
    case Event.emit(state.channel, :cancelled, request_ref: reference) do
      :ok ->
        {:reply, :ok, %{state | request: nil, awaiting: nil, last_terminal_request: reference}}

      _failure ->
        {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: nil, last_terminal_request: reference} = state
      ),
      do: {:reply, :ok, %{state | last_terminal_request: nil}}

  def handle_call({:cancel, _reference, _playback}, _from, state),
    do: {:reply, {:error, :stale_request}, state}

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def handle_info(message, %{request: reference, awaiting: credit} = state) do
    case TTSProvider.credit(message, state.channel, reference, credit) do
      :ok ->
        case Event.emit(state.channel, :completed, request_ref: reference) do
          :ok ->
            {:noreply, %{state | request: nil, awaiting: nil, last_terminal_request: reference}}

          _failure ->
            {:stop, {:shutdown, :session_failed}, state}
        end

      :stale ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :guide_tts_provider)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
