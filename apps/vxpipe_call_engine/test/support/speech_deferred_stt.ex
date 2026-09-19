defmodule Vxpipe.CallEngine.SpeechDeferredSTT do
  @moduledoc false
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{Channel, Event, STTProvider}

  @impl true
  def configure(options), do: MorseSession.configure(options)

  @impl true
  def start_link(options), do: STTProvider.start_link(__MODULE__, options)

  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:audio, audio}, 5_000)

  @impl true
  def close(pid), do: GenServer.stop(pid, :normal, 5_000)

  @impl true
  def init(options) do
    channel = Keyword.fetch!(options, :channel)
    :ok = Channel.bind(channel)
    :ok = Event.emit(channel, :ready, readiness: :initialized)
    {:ok, %{pending: nil}}
  end

  @impl true
  def handle_call({:audio, audio}, _from, %{pending: nil} = state),
    do: {:reply, :ok, %{state | pending: audio}}

  def handle_call({:audio, _audio}, _from, state), do: {:reply, {:error, :busy}, state}

  def handle_call(:complete_input, _from, state),
    do: {:reply, byte_size(state.pending), %{state | pending: nil}}

  def handle_call(:fail_input, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :deferred_stt)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
