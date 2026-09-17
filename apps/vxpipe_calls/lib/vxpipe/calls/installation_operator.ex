defmodule Vxpipe.Calls.InstallationOperator do
  @moduledoc "Explicit installation-wide authority for bounded operator workflows."

  @enforce_keys [:grant]
  defstruct grant: :installation_operator

  @opaque t :: %__MODULE__{grant: :installation_operator}

  @spec authority() :: t()
  def authority, do: %__MODULE__{grant: :installation_operator}
end
