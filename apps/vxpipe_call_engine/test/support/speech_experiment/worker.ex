defmodule Vxpipe.CallEngine.SpeechExperiment.Worker do
  @moduledoc false
  use GenServer
  alias Vxpipe.CallEngine.Provider.MorseCode.{Decoder, Encoder}
  alias Vxpipe.CallEngine.SpeechExperiment.Control

  def address(token),
    do: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, token}}}

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: address(Keyword.fetch!(options, :token)))

  def init(options) do
    {:ok, decoder} = Decoder.new(Keyword.fetch!(options, :config))

    {:ok,
     %{
       config: Keyword.fetch!(options, :config),
       decoder: decoder,
       control: Control.address(Keyword.fetch!(options, :token)),
       encoder: nil,
       generation: nil,
       options: options
     }, {:continue, :initialize}}
  end

  def handle_continue(:initialize, state) do
    if Keyword.get(state.options, :hold_start, false) do
      send(Keyword.fetch!(state.options, :observer), {:experiment_held, self()})

      receive do
        :release_start -> :ok
      end
    end

    emit(state, :ready)
    {:noreply, %{state | options: []}}
  end

  def handle_cast({:audio, command, audio}, state) do
    {:ok, decoder, events} = Decoder.push(state.decoder, audio)
    Enum.each(events, &emit(state, {:stt, &1}))
    emit(state, {:accepted, command, :ok})
    {:noreply, %{state | decoder: decoder}}
  end

  def handle_cast({:speak, generation, text}, state) do
    {:ok, encoder} = Encoder.start(state.config, text)
    state = %{state | encoder: encoder, generation: generation}
    emit(state, {:tts, generation, :started})
    {:noreply, next_audio(state)}
  end

  def handle_cast({:credit, generation, :ok}, %{generation: generation} = state),
    do: {:noreply, next_audio(state)}

  def handle_cast({:cancel, generation}, %{generation: generation} = state),
    do: {:noreply, %{state | encoder: nil, generation: nil}}

  def handle_cast(_message, state), do: {:noreply, state}

  defp next_audio(%{encoder: nil} = state), do: state

  defp next_audio(state) do
    case Encoder.next(state.encoder, div(state.config.sample_rate, 50)) do
      {:ok, audio, encoder} ->
        emit(state, {:tts, state.generation, {:audio, audio}})
        %{state | encoder: encoder}

      :done ->
        emit(state, {:tts, state.generation, :completed})
        %{state | encoder: nil, generation: nil}
    end
  end

  defp emit(state, event), do: send(GenServer.whereis(state.control), {:semantic, event})
end
