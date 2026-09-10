defmodule Vxpipe.CallEngine.CallLifecycle.Timer do
  @moduledoc false

  @callback schedule(pid(), reference(), atom(), pos_integer(), keyword()) :: term()
  @callback cancel(term(), keyword()) :: :ok
end
