defmodule Vxpipe.CallEngine.Tool.Call do
  @moduledoc false

  @enforce_keys [:id, :name, :arguments]
  defstruct @enforce_keys ++ [provider_metadata: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          arguments: map(),
          provider_metadata: map()
        }
end
