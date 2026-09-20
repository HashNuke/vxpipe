defmodule Vxpipe.CallEngine.Readiness.Provider do
  @moduledoc false

  @spec connected(:preparing | :ready | :failed) :: :ready | :failed
  def connected(:failed), do: :failed
  def connected(status) when status in [:preparing, :ready], do: :ready
end
