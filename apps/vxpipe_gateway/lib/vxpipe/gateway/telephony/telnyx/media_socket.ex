defmodule Vxpipe.Gateway.Telephony.Telnyx.MediaSocket do
  @moduledoc false

  @behaviour WebSock

  alias Vxpipe.Gateway.Telephony.MediaBinding

  @impl true
  def init(%{binding: %MediaBinding{} = binding}) do
    monitor = Process.monitor(binding.leg)
    {:ok, %{binding: binding, leg_monitor: monitor}}
  end

  @impl true
  def handle_in({_message, opcode}, state) when opcode in [:text, :binary] do
    {:stop, :media_not_attached, {1008, "media not attached"}, state}
  end

  @impl true
  def handle_info({:vxpipe_telnyx_socket_send, message}, state) when is_binary(message) do
    {:push, {:text, message}, state}
  end

  def handle_info({:DOWN, monitor, :process, leg, _reason}, state)
      when monitor == state.leg_monitor and leg == state.binding.leg do
    {:stop, :normal, {1000, "leg ended"}, state}
  end

  def handle_info(_message, state), do: {:ok, state}
end
