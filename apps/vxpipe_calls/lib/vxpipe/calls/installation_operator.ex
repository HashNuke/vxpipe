defmodule Vxpipe.Calls.InstallationOperator do
  @moduledoc "Explicit installation-wide authority for bounded operator workflows."

  @enforce_keys [:grant]
  defstruct grant: :installation_operator, api_key_id: nil, credential_kind: nil

  @opaque t :: %__MODULE__{
            grant: :installation_operator,
            api_key_id: String.t() | nil,
            credential_kind: :platform_api_key | :legacy_operator_api_key | nil
          }

  @spec authority() :: t()
  def authority, do: %__MODULE__{grant: :installation_operator}
end
