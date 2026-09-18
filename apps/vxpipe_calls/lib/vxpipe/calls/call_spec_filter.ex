defmodule Vxpipe.Calls.CallSpecFilter do
  @moduledoc "One bounded call spec option available to the operator call directory."

  @enforce_keys [:id, :name]
  defstruct @enforce_keys

  @type t :: %__MODULE__{id: String.t(), name: String.t() | nil}
end
