defmodule Vxpipe.Gateway.Media.InputPrepared do
  @moduledoc false

  @derive Membrane.EventProtocol
  @enforce_keys [:reference]
  defstruct @enforce_keys
end
