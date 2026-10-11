defmodule Vxpipe.CallEngine.SpeechOnsetProbe do
  @moduledoc false
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Channel, Event, STTProvider}

  @impl true
  defdelegate models(), to: MorseSession
  @impl true
  def configure(options) do
    {encoding, options} = Keyword.pop(options, :encoding, :linear16)

    with {:ok, descriptor} <- MorseSession.configure(options) do
      format =
        if encoding == :opus,
          do:
            Map.take(Map.put(descriptor.format, :encoding, :opus), [
              :encoding,
              :sample_rate,
              :channels,
              :container
            ]),
          else: descriptor.format

      {:ok, %{descriptor | format: format}}
    end
  end

  @impl true
  def start_link(options), do: STTProvider.start_link(__MODULE__, options)
  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:audio, audio})
  @impl true
  def close(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init(options) do
    channel = Keyword.fetch!(options, :channel)
    owner = options |> Keyword.fetch!(:private) |> Keyword.fetch!(:observer)
    :ok = Channel.bind(channel)
    send(owner, {:recognizer, self(), Keyword.fetch!(options, :allocation)})
    :ok = Event.emit(channel, :ready, readiness: :initialized)
    {:ok, %{channel: channel, owner: owner}}
  end

  @impl true
  def handle_call({:audio, audio}, _from, state) do
    send(state.owner, {:recognized_audio, audio})
    {:reply, :ok, state}
  end

  def handle_call({:emit, kind, fields}, _from, state),
    do: {:reply, Event.emit(state.channel, kind, fields), state}
end
