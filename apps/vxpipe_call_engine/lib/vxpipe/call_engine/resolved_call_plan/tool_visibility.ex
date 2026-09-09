defmodule Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility do
  @moduledoc false

  @enforce_keys [:default, :overrides]
  defstruct @enforce_keys

  @type level :: :hidden | :metadata | :full
  @type t :: %__MODULE__{
          default: level(),
          overrides: %{String.t() => %{String.t() => level()}}
        }

  @spec hidden() :: t()
  def hidden, do: %__MODULE__{default: :hidden, overrides: %{}}
end
