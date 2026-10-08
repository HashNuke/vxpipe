defmodule Vxpipe.CallEngine.SpeechTTSCompletionProbe do
  @moduledoc false
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.TTSProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Channel, Event, TTSProvider}

  @impl true
  def models, do: [Vxpipe.CallEngine.Speech.Model.new("test", "Test provider", true)]

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
    observer = Keyword.fetch!(private, :observer)
    :ok = Channel.bind(channel)
    :ok = Event.emit(channel, :ready, readiness: :initialized)
    {:ok, %{channel: channel, observer: observer}}
  end

  @impl true
  def handle_call({:speak, reference, _text}, _from, state) do
    :ok =
      Event.emit(state.channel, :input_submitted,
        request_ref: reference,
        provenance: :locally_measured
      )

    {:ok, credit} = Channel.submit(state.channel, reference, <<0, 0>>)

    receive do
      {:vxpipe_speech_credit, _channel, ^reference, ^credit, :ok} -> :ok
    after
      2_000 -> raise "consumer did not acknowledge probe audio"
    end

    :ok = Event.emit(state.channel, :completed, request_ref: reference)
    send(state.observer, {:tts_completion_callback_held, reference})

    receive do
      {:release_callback, result} -> {:reply, result, state}
    after
      2_000 -> {:reply, {:error, :session_failed}, state}
    end
  end
end
