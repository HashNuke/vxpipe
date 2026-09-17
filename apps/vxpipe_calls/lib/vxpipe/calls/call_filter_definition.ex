defmodule Vxpipe.Calls.CallFilterDefinition do
  @moduledoc "One bounded definition option available to the operator call directory."

  @enforce_keys [:id, :name]
  defstruct @enforce_keys

  @type t :: %__MODULE__{id: String.t(), name: String.t() | nil}
end
