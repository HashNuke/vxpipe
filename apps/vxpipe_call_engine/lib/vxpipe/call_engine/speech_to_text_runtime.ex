defmodule Vxpipe.CallEngine.SpeechToTextRuntime do
  @moduledoc false

  @enforce_keys [:provider, :transport, :media_ingress]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          provider: {module(), term()},
          transport: {module(), keyword()},
          media_ingress: keyword()
        }
end
