defmodule Vxpipe.CallEngine.Readiness.Provider do
  @moduledoc false

  @spec initial_status(module()) :: :preparing | :ready | :failed
  def initial_status(module) do
    if function_exported?(module, :readiness_mode, 0) do
      case module.readiness_mode() do
        :initialized -> :ready
        :provider_connected -> :preparing
        _unsupported -> :failed
      end
    else
      :failed
    end
  end

  @spec connected(:preparing | :ready | :failed) :: :ready | :failed
  def connected(:failed), do: :failed
  def connected(status) when status in [:preparing, :ready], do: :ready
end
