defmodule Vxpipe.CallEngine.TestTextToSpeechTransport do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Provider.TextToSpeech.Transport

  @impl true
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def send_control(transport, payload), do: GenServer.call(transport, {:send_control, payload})

  @impl true
  def close(transport), do: GenServer.call(transport, :close)

  def deliver_control(transport, payload), do: GenServer.cast(transport, {:control, payload})
  def deliver_audio(transport, payload), do: GenServer.cast(transport, {:audio, payload})

  def deliver_audio_with_result(transport, payload) do
    reference = make_ref()
    GenServer.cast(transport, {:audio_with_result, reference, payload})
    reference
  end

  def disconnect(transport, reason), do: GenServer.cast(transport, {:disconnect, reason})

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    transport_options = Keyword.fetch!(options, :transport_options)
    observer = Keyword.fetch!(transport_options, :observer)
    connection = Keyword.fetch!(options, :connection)
    await_start_permission(transport_options, observer, connection)
    send(observer, {:test_tts_transport_started, self(), connection})
    {:ok, %{observer: observer, owner: owner}}
  end

  @impl true
  def handle_call({:send_control, payload}, _from, state) do
    send(state.observer, {:test_tts_control, self(), payload})
    {:reply, :ok, state}
  end

  def handle_call(:close, _from, state) do
    send(state.observer, {:test_tts_transport_closed, self()})
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({:control, payload}, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:control, payload}})
    {:noreply, state}
  end

  def handle_cast({:audio, payload}, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:audio, payload}})
    {:noreply, state}
  end

  def handle_cast({:audio_with_result, reference, payload}, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:audio, reference, payload}})
    {:noreply, state}
  end

  def handle_cast({:disconnect, reason}, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:closed, reason}})
    {:noreply, state}
  end

  @impl true
  def handle_info({:vxpipe_tts_audio_result, owner, reference, result}, %{owner: owner} = state) do
    send(state.observer, {:test_tts_audio_result, reference, result})
    {:noreply, state}
  end

  defp await_start_permission(options, observer, connection) do
    case {Keyword.get(options, :start_counter), Keyword.get(options, :block_after_starts)} do
      {counter, successful_starts} when is_reference(counter) and is_integer(successful_starts) ->
        start_number = :atomics.add_get(counter, 1, 1)

        if start_number > successful_starts do
          send(observer, {:test_tts_transport_start_blocked, self(), connection})

          receive do
            :release_test_tts_transport_start -> :ok
          end
        end

      _uncontrolled ->
        :ok
    end
  end
end
