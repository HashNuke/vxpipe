defmodule Vxpipe.CallEngine.SpeechTopologySTT do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder}

  def start_link(owner), do: GenServer.start_link(__MODULE__, owner)

  @impl true
  def init(owner) do
    {:ok, config} = Config.new(sample_rate: 8_000, unit_duration_ms: 20)
    {:ok, decoder} = Decoder.new(config)
    {:ok, %{owner: owner, decoder: decoder}}
  end

  @impl true
  def handle_call({:turn, reference, pcm}, {caller, _tag}, %{owner: caller} = state) do
    case Decoder.push(state.decoder, pcm) do
      {:ok, decoder, events} ->
        Enum.each(events, &publish(state.owner, reference, &1))
        {:reply, :ok, %{state | decoder: decoder}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:turn, _reference, _pcm}, _from, state),
    do: {:reply, {:error, :not_owner}, state}

  defp publish(owner, reference, :started),
    do: send(owner, {:topology_speech_started, reference})

  defp publish(owner, reference, {:partial, text}),
    do: send(owner, {:topology_text, reference, text})

  defp publish(owner, reference, {:final, text}),
    do: send(owner, {:topology_turn_end, reference, text})
end
