defmodule Vxpipe.CallEngine.SpeechTopologyEvent do
  @moduledoc false

  @enforce_keys [:ref, :kind, :request_ref]
  defstruct @enforce_keys ++ [:provider_request_id]
end
