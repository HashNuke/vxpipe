defmodule Vxpipe.AgentRuntime.ModelTool do
  @moduledoc "A model-visible tool projection with no private execution binding."

  alias Vxpipe.AgentRuntime.ToolDescriptor

  @enforce_keys [:name, :description, :input_schema]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map()
        }

  @spec from_descriptor(ToolDescriptor.t()) :: t()
  def from_descriptor(%ToolDescriptor{} = descriptor) do
    %__MODULE__{
      name: descriptor.name,
      description: descriptor.description,
      input_schema: descriptor.input_schema
    }
  end
end
