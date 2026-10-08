defmodule Vxpipe.CallEngine.TestGoogleSTSTransport do
  @moduledoc false

  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def send_control(socket, message), do: GenServer.call(socket, {:control, message})
  def send_audio(socket, audio), do: GenServer.call(socket, {:audio, audio})

  def send_text(socket, text) do
    with {:ok, payload} <- Vxpipe.Providers.Google.STS.encode_text(text),
         do: GenServer.call(socket, {:control, payload})
  end

  def send_activity(socket, boundary) do
    with {:ok, payload} <- Vxpipe.Providers.Google.STS.encode_activity(boundary),
         do: GenServer.call(socket, {:control, payload})
  end

  def send_tool_result(socket, call_id, name, result) do
    with {:ok, payload} <- Vxpipe.Providers.Google.STS.encode_tool_result(call_id, name, result),
         do: GenServer.call(socket, {:control, payload})
  end

  def close(socket), do: GenServer.call(socket, :close)
  def retire(socket), do: GenServer.cast(socket, :retire)
  def acknowledge_retirement(socket), do: GenServer.cast(socket, :retired)
  def finish_retirement(socket), do: GenServer.stop(socket, :normal)
  def deliver(socket, message), do: GenServer.cast(socket, {:deliver, message})
  def disconnect(socket), do: GenServer.cast(socket, :disconnect)
  def reject_session_active(socket), do: GenServer.cast(socket, :session_active)

  @impl true
  def init(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)
    owner = Keyword.fetch!(options, :owner)
    send(observer, {:test_google_sts_started, self(), Keyword.fetch!(options, :connection)})
    if Keyword.get(options, :deferred, false), do: send(owner, {:vxpipe_socket_connected, self()})

    ready_on_start =
      options |> Keyword.fetch!(:transport_options) |> Keyword.get(:ready_on_start, false)

    retire_ack? = options |> Keyword.fetch!(:transport_options) |> Keyword.get(:retire_ack?, true)

    {:ok,
     %{observer: observer, owner: owner, ready_on_start: ready_on_start, retire_ack?: retire_ack?}}
  end

  @impl true
  def handle_call({:control, message}, _from, state) do
    send(state.observer, {:test_google_sts_control, self(), message})

    if state.ready_on_start,
      do: send(state.owner, {:vxpipe_sts_transport, self(), {:message, ~s({"setupComplete":{}})}})

    {:reply, :ok, state}
  end

  def handle_call({:audio, audio}, _from, state) do
    send(state.observer, {:test_google_sts_audio, self(), audio})
    {:reply, :ok, state}
  end

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def handle_cast(:retire, state) do
    send(state.observer, {:test_google_sts_retire, self()})

    if state.retire_ack? do
      send(state.owner, {:vxpipe_socket_retired, self()})
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_cast(:retired, state) do
    send(state.owner, {:vxpipe_socket_retired, self()})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:deliver, message}, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:message, message}})
    {:noreply, state}
  end

  def handle_cast(:disconnect, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:closed, :connection_lost}})
    {:noreply, state}
  end

  def handle_cast(:session_active, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:closed, :session_active}})
    {:stop, :normal, state}
  end
end
