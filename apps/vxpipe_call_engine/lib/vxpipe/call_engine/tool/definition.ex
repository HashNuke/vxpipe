defmodule Vxpipe.CallEngine.Tool.Definition do
  @moduledoc false

  @enforce_keys [:name, :description, :parameters]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: map()
        }
end
