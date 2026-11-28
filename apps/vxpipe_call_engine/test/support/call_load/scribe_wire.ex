defmodule Vxpipe.CallEngine.CallLoad.ScribeWire do
  @moduledoc "Local Scribe transport for the prerecorded yes utterance. Silero owns endpointing."
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, Keyword.fetch!(options, :owner))
  def send_audio(pid, pcm), do: GenServer.call(pid, {:audio, pcm})
  def commit(pid), do: GenServer.call(pid, :commit)

  @impl true
  def init(owner) do
    emit(owner, {:ready, "load-scribe"})
    {:ok, {owner, :waiting}}
  end

  @impl true
  def handle_call({:audio, pcm}, _from, {owner, :waiting} = state) do
    if pcm == :binary.copy(<<0>>, byte_size(pcm)) do
      {:reply, :ok, state}
    else
      emit(owner, {:partial, "Ye"})
      {:reply, :ok, {owner, :speaking}}
    end
  end

  def handle_call({:audio, _pcm}, _from, state), do: {:reply, :ok, state}

  def handle_call(:commit, _from, {owner, _phase}) do
    emit(owner, {:segment, "Yes"})
    {:reply, :ok, {owner, :waiting}}
  end

  defp emit(owner, event), do: send(owner, {:vxpipe_scribe_transport, self(), {:event, event}})
end
