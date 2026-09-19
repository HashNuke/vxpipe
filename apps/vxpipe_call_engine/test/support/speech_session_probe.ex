defmodule Vxpipe.CallEngine.SpeechSessionProbe do
  @moduledoc false
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Channel, Event}

  @impl true
  def configure(options), do: MorseSession.configure(options)

  @impl true
  def start_link(options) do
    case Keyword.get(Keyword.fetch!(options, :private), :start_error) do
      nil -> Vxpipe.CallEngine.Speech.STTProvider.start_link(__MODULE__, options)
      reason -> {:error, reason}
    end
  end

  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:audio, audio}, :infinity)

  @impl true
  def close(pid), do: GenServer.call(pid, :close, :infinity)

  @impl true
  def init(options) do
    private = Keyword.fetch!(options, :private)
    observer = Keyword.fetch!(private, :observer)
    channel = Keyword.fetch!(options, :channel)

    if Keyword.get(private, :trap_exits?, false), do: Process.flag(:trap_exit, true)

    if Keyword.get(private, :hold_before_bind?, false) do
      send(observer, {:probe_before_bind, self(), channel})

      receive do
        :release_bind -> :ok
      end
    end

    :ok = Channel.bind(channel)
    :ok = Event.emit(channel, :ready, readiness: :initialized)
    send(observer, {:probe_initializing, self(), channel})

    if Keyword.get(private, :hold_start?, false) do
      receive do
        :release_start -> :ok
      end
    end

    {:ok,
     %{
       observer: observer,
       channel: channel,
       hold_input?: Keyword.get(private, :hold_input?, false)
     }}
  end

  @impl true
  def handle_call({:audio, _audio}, _from, state) do
    send(state.observer, {:probe_input, self()})

    if state.hold_input? do
      receive do
        :release_input -> :ok
      end
    end

    {:noreply, state}
  end

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}
end
