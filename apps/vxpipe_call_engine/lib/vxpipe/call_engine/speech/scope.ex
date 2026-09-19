defmodule Vxpipe.CallEngine.Speech.Scope do
  @moduledoc "An explicitly supervised local speech capability. Contains no provider configuration."
  @enforce_keys [:tree, :control, :sessions, :admissions]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end
