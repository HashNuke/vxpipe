defmodule Vxpipe.CallEngine.TestSpeechWireSession do
  @moduledoc false
  @behaviour WebSock

  @impl true
  def init(owner) do
    send(owner, {:speech_wire_connected, self()})
    {:ok, owner}
  end

  @impl true
  def handle_in({data, opcode: opcode}, owner) do
    send(owner, {:speech_wire_frame, self(), opcode, data})
    {:ok, owner}
  end

  @impl true
  def handle_control({data, opcode: opcode}, owner) do
    send(owner, {:speech_wire_frame, self(), opcode, data})
    {:ok, owner}
  end

  @impl true
  def handle_info({:send, frames}, owner), do: {:push, frames, owner}
  def handle_info(:close, owner), do: {:stop, :normal, owner}

  @impl true
  def terminate(_reason, owner) do
    send(owner, {:speech_wire_closed, self()})
    :ok
  end
end
