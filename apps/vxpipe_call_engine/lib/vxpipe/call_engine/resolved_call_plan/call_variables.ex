defmodule Vxpipe.CallEngine.ResolvedCallPlan.CallVariables do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan.VariableSection

  defstruct sections: %{}

  @type t :: %__MODULE__{sections: %{optional(String.t()) => VariableSection.t()}}
end
