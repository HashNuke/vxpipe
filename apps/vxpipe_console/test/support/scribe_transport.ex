defmodule Vxpipe.Console.Test.ScribeTransport do
  @moduledoc false
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def send_audio(connection, audio), do: GenServer.call(connection, {:audio, byte_size(audio)})
  def commit(connection), do: GenServer.call(connection, :commit)
  def deliver(connection, event), do: GenServer.call(connection, {:deliver, event})

  @impl true
  def init(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)
    send(observer, {:configured_scribe_started, self()})
    {:ok, %{owner: Keyword.fetch!(options, :owner)}, {:continue, :ready}}
  end

  @impl true
  def handle_continue(:ready, state) do
    send(
      state.owner,
      {:vxpipe_scribe_transport, self(), {:event, {:ready, "synthetic-configured-scribe"}}}
    )

    {:noreply, state}
  end

  @impl true
  def handle_call({:audio, _size}, _from, state), do: {:reply, :ok, state}

  def handle_call({:deliver, event}, _from, state) do
    send(state.owner, {:vxpipe_scribe_transport, self(), {:event, event}})
    {:reply, :ok, state}
  end

  def handle_call(:commit, _from, state) do
    send(
      state.owner,
      {:vxpipe_scribe_transport, self(), {:event, {:segment, "Public telescope."}}}
    )

    {:reply, :ok, state}
  end
end
