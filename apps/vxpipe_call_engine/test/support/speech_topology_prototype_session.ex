defmodule Vxpipe.CallEngine.SpeechTopologyPrototype.Session do
  @moduledoc false
  @enforce_keys [
    :topology,
    :ref,
    :supervisor,
    :channel,
    :input,
    :provider,
    :output,
    :usage,
    :timeout
  ]
  defstruct @enforce_keys
end
