defmodule Vxpipe.Calls.InstallationOperator do
  @moduledoc "Explicit installation-wide authority for bounded operator workflows."

  @enforce_keys [:grant]
  defstruct grant: :installation_operator, api_key_id: nil

  @opaque t :: %__MODULE__{grant: :installation_operator, api_key_id: String.t() | nil}

  @spec authority() :: t()
  def authority, do: %__MODULE__{grant: :installation_operator}
end
