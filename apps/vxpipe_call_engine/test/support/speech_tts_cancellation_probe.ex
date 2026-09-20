defmodule Vxpipe.CallEngine.SpeechTTSCancellationProbe do
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
       order: Keyword.fetch!(private, :order),
       request: nil
     }}
  end

  @impl true
  def handle_call({:speak, reference, _text}, _from, state) do
    :ok =
      Event.emit(state.channel, :input_submitted,
        request_ref: reference,
        provenance: :locally_measured
      )

    send(state.observer, {:probe_speak, reference})
    {:reply, :ok, %{state | request: reference}}
  end

  def handle_call({:cancel, reference, playback}, _from, %{request: reference} = state) do
    send(state.observer, {:probe_cancel, reference, playback})

    if state.order == :terminal_first do
      :ok = Event.emit(state.channel, :cancelled, request_ref: reference)
      send(state.observer, :probe_terminal_accepted)

      receive do
        :release_callback -> :ok
      end
    end

    {:reply, :ok, state}
  end

  def handle_call(:emit_cancelled, _from, state),
    do: {:reply, Event.emit(state.channel, :cancelled, request_ref: state.request), state}
end
