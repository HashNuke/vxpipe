defmodule Vxpipe.CallEngine.SpeechTTSUsageProbe do
  @moduledoc false
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.TTSProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Channel, Event, TTSProvider}

  @impl true
  def configure(options), do: MorseSession.configure(options)

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
    channel = Keyword.fetch!(options, :channel)
    private = Keyword.fetch!(options, :private)
    :ok = Channel.bind(channel)
    :ok = Event.emit(channel, :ready, readiness: :initialized)

    {:ok,
     %{
       channel: channel,
       observer: Keyword.fetch!(private, :observer),
       hold_cancel?: Keyword.get(private, :hold_cancel?, false),
       id_at: Keyword.get(private, :id_at, :submission),
       audio?: Keyword.get(private, :audio?, true),
       request: nil,
       provider_request_id: nil,
       terminal?: false
     }}
  end

  @impl true
  def handle_call({:speak, reference, _text}, _from, state) do
    provider_request_id = "synthetic-request-#{System.unique_integer([:positive])}"
    fields = [request_ref: reference, provenance: :locally_measured]

    fields =
      if state.id_at == :submission,
        do: fields ++ [provider_request_id: provider_request_id],
        else: fields

    with :ok <- Event.emit(state.channel, :input_submitted, fields),
         {:ok, _credit} <- submit_audio(state, reference) do
      send(state.observer, {:usage_probe_submitted, reference, provider_request_id})

      {:reply, :ok,
       %{
         state
         | request: reference,
           provider_request_id: provider_request_id,
           terminal?: false
       }}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call(:complete, _from, %{request: reference, terminal?: false} = state) do
    fields = [request_ref: reference]

    fields =
      if state.id_at == :terminal,
        do: fields ++ [provider_request_id: state.provider_request_id],
        else: fields

    result = Event.emit(state.channel, :completed, fields)
    state = if result == :ok, do: %{state | terminal?: true}, else: state
    {:reply, result, state}
  end

  def handle_call({:cancel, reference, _playback}, _from, %{request: reference} = state) do
    if state.hold_cancel? do
      send(state.observer, {:usage_probe_cancel_held, self(), reference})

      receive do
        :release_usage_probe_cancel -> :ok
      end
    end

    result =
      if state.terminal? do
        :ok
      else
        Event.emit(state.channel, :cancelled,
          request_ref: reference,
          provider_request_id: state.provider_request_id
        )
      end

    state = if result == :ok, do: %{state | terminal?: true}, else: state
    {:reply, result, state}
  end

  def handle_call({:cancel, _reference, _playback}, _from, state),
    do: {:reply, {:error, :stale_request}, state}

  @impl true
  def handle_info({:vxpipe_speech_credit, _channel, request, credit, :ok}, state) do
    send(state.observer, {:usage_probe_audio_credited, request, credit})
    {:noreply, state}
  end

  defp submit_audio(%{audio?: true, channel: channel}, reference),
    do: Channel.submit(channel, reference, :binary.copy(<<1, 0>>, 160))

  defp submit_audio(%{audio?: false}, _reference), do: {:ok, nil}
end
