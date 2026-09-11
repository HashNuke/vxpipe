defmodule Vxpipe.CallEngine.MediaPolicy.Enforcer do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot

  @spec apply(pid(), Snapshot.t(), timeout()) :: :ok | {:error, term()}
  def apply(enforcer, %Snapshot{} = snapshot, timeout)
      when is_pid(enforcer) and is_integer(timeout) and timeout > 0 do
    try do
      case GenServer.call(enforcer, {:vxpipe_apply_media_policy, snapshot}, timeout) do
        :ok -> :ok
        {:error, _reason} = error -> error
        _invalid -> {:error, :invalid_acknowledgement}
      end
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end
end
