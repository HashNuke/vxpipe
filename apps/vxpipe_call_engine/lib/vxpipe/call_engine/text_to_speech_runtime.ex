defmodule Vxpipe.CallEngine.TextToSpeechRuntime do
  @moduledoc false

  @enforce_keys [:provider, :transport, :maximum_requests]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          provider: {module(), term()},
          transport: {module(), keyword()},
          maximum_requests: pos_integer()
        }
end
