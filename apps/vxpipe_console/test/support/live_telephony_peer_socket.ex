defmodule Vxpipe.Console.Test.LiveTelephonyPeerSocket do
  @moduledoc false
  @behaviour WebSock

  alias Vxpipe.Gateway.TestObservedTelephonySocket

  @impl true
  def init(options) do
    with {:ok, state} <- TestObservedTelephonySocket.init(options) do
      binding = options.binding
      key = {binding.tenant_id, binding.call_id, binding.participant_id}

      case Registry.register(__MODULE__.Registry, key, binding) do
        {:ok, _owner} -> {:ok, state}
        {:error, _reason} -> {:stop, :peer_already_connected, state}
      end
    end
  end

  def binding(tenant_id, call_id, participant_id) do
    case Registry.lookup(__MODULE__.Registry, {tenant_id, call_id, participant_id}) do
      [{_socket, binding}] -> {:ok, binding}
      [] -> {:error, :peer_not_connected}
    end
  end

  @impl true
  defdelegate handle_in(frame, state), to: TestObservedTelephonySocket

  @impl true
  defdelegate handle_info(message, state), to: TestObservedTelephonySocket
end
