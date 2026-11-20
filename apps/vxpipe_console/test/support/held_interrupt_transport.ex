defmodule Vxpipe.Console.Test.HeldInterruptTransport do
  @moduledoc false
  use GenServer
  alias Vxpipe.CallEngine.TestTextToSpeechTransport, as: Transport

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  defdelegate send_control(transport, payload), to: Transport
  defdelegate close(transport), to: Transport
  defdelegate close(transport, goodbye), to: Transport
  def release(transport), do: GenServer.call(transport, :release_interrupt)

  @impl true
  defdelegate init(options), to: Transport

  @impl true
  def handle_call({:send_control, payload} = message, from, state) do
    if JSON.decode!(payload)["type"] == "Interrupt" do
      send(state.observer, {:held_provider_interrupt, self(), payload})
      {:noreply, Map.put(state, :held_interrupt, from)}
    else
      Transport.handle_call(message, from, state)
    end
  end

  def handle_call(:release_interrupt, _from, state) do
    GenServer.reply(Map.fetch!(state, :held_interrupt), :ok)
    {:reply, :ok, Map.delete(state, :held_interrupt)}
  end

  def handle_call(message, from, state), do: Transport.handle_call(message, from, state)
  @impl true
  defdelegate handle_cast(message, state), to: Transport
  @impl true
  defdelegate handle_info(message, state), to: Transport
end
